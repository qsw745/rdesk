package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"time"
)

type fault string

func (f fault) Error() string { return string(f) }

var identifier = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)

func magicPacket(s string) ([]byte, error) {
	mac, err := net.ParseMAC(s)
	if err != nil || len(mac) != 6 || mac[0]&1 != 0 || bytes.Equal(mac, make([]byte, 6)) {
		return nil, fault("invalid_mac")
	}
	result := bytes.Repeat([]byte{255}, 6)
	for i := 0; i < 16; i++ {
		result = append(result, mac...)
	}
	return result, nil
}

func validOrigin(s string) error {
	u, err := url.Parse(s)
	if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || (u.Path != "" && u.Path != "/") || u.RawQuery != "" || u.Fragment != "" {
		return fault("invalid_https_origin")
	}
	return nil
}

type HTTPError struct{ Status int }

func (e HTTPError) Error() string { return fmt.Sprintf("http_%d", e.Status) }

type API struct {
	origin, token string
	client        *http.Client
}

func newAPI(origin, token string) *API {
	return &API{origin: origin, token: token, client: &http.Client{
		Timeout: 12 * time.Second,
		// Explicit certificates, no redirects and no environment proxy credentials.
		Transport:     &http.Transport{TLSHandshakeTimeout: 5 * time.Second, ResponseHeaderTimeout: 10 * time.Second, MaxIdleConnsPerHost: 2, IdleConnTimeout: 60 * time.Second},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}}
}
func (a *API) call(ctx context.Context, method, path string, body, out any) (int, error) {
	if err := validOrigin(a.origin); err != nil {
		return 0, err
	}
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return 0, fault("invalid_request")
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, a.origin+path, reader)
	if err != nil {
		return 0, fault("invalid_request")
	}
	req.Header.Set("Content-Type", "application/json")
	if a.token != "" {
		req.Header.Set("Authorization", "Bearer "+a.token)
	}
	res, err := a.client.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return 0, ctx.Err()
		}
		return 0, fault("network_or_tls")
	}
	defer res.Body.Close()
	data, err := io.ReadAll(io.LimitReader(res.Body, 65537))
	if err != nil || len(data) > 65536 {
		return res.StatusCode, fault("invalid_response")
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return res.StatusCode, HTTPError{res.StatusCode}
	}
	if out != nil && res.StatusCode != 204 {
		if err := json.Unmarshal(data, out); err != nil {
			return res.StatusCode, fault("invalid_response")
		}
	}
	return res.StatusCode, nil
}

type Job struct {
	ID            string `json:"id"`
	MAC           string `json:"mac"`
	RemainingMS   int64  `json:"remaining_ms"`
	SetupComplete bool   `json:"setup_complete"`
}
type Entry struct {
	Expires int64  `json:"expires_ms"`
	Phase   string `json:"phase"`
	Error   string `json:"error,omitempty"`
	Count   int    `json:"packets"`
	Ack     bool   `json:"receipt_acknowledged"`
}
type Journal struct {
	Items map[string]Entry `json:"requests"`
	dir   string
}

func loadJournal(dir string) (*Journal, error) {
	j := &Journal{dir: dir, Items: map[string]Entry{}}
	b, err := readPrivate(filepath.Join(dir, "journal.json"), 1024*1024)
	if errors.Is(err, os.ErrNotExist) {
		return j, nil
	}
	if err != nil {
		return nil, err
	}
	if json.Unmarshal(b, j) != nil || j.Items == nil || len(j.Items) > 2048 {
		return nil, fault("journal_corrupt")
	}
	for id, e := range j.Items {
		if !identifier.MatchString(id) || (e.Phase != "reserved" && e.Phase != "sent" && e.Phase != "failed") {
			return nil, fault("journal_corrupt")
		}
	}
	return j, nil
}
func (j *Journal) save() error { return atomicJSON(j.dir, "journal.json", j) }
func atomicJSON(dir, name string, value any) error {
	b, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fault("storage_failed")
	}
	f, err := os.CreateTemp(dir, ".write-")
	if err != nil {
		return fault("storage_failed")
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err = f.Write(b); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil || closeErr != nil {
		return fault("storage_failed")
	}
	if err = os.Rename(tmp, filepath.Join(dir, name)); err != nil {
		return fault("storage_failed")
	}
	d, err := os.Open(dir)
	if err != nil {
		return fault("storage_failed")
	}
	defer d.Close()
	if d.Sync() != nil {
		return fault("storage_failed")
	}
	return nil
}
func readPrivate(path string, limit int64) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() > limit {
		return nil, fault("unsafe_private_file")
	}
	return os.ReadFile(path)
}

type Event struct {
	Time    string `json:"time"`
	Event   string `json:"event"`
	Request string `json:"request_id,omitempty"`
	Code    string `json:"code,omitempty"`
	Packets int    `json:"packets,omitempty"`
}
type EventLog struct {
	dir    string
	failed bool
}

func (l *EventLog) write(event, id, code string, n int) {
	ok := false
	defer func() {
		if !ok && !l.failed {
			fmt.Fprintln(os.Stderr, "诊断日志暂不可写（log_write_failed），请检查日志目录权限和空间。")
		}
		l.failed = !ok
	}()
	// All callers supply constants or validated IDs; never log response bodies,
	// HTTP errors containing URLs, account data, MAC addresses or bearer tokens.
	b, _ := json.Marshal(Event{time.Now().UTC().Format(time.RFC3339Nano), event, id, code, n})
	path := filepath.Join(l.dir, "events.jsonl")
	if st, err := os.Lstat(path); err == nil {
		if !st.Mode().IsRegular() || st.Mode().Perm()&0077 != 0 {
			return
		}
		if st.Size() > 256*1024 {
			if os.Rename(path, filepath.Join(l.dir, "events.previous.jsonl")) != nil {
				return
			}
		}
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return
	}
	written, writeErr := f.Write(append(b, '\n'))
	closeErr := f.Close()
	ok = writeErr == nil && closeErr == nil && written == len(b)+1
}

type Engine struct {
	api     *API
	journal *Journal
	check   func() error
	send    func([]byte) error
	log     *EventLog
}

func (e *Engine) record(id string, item Entry) error {
	e.journal.Items[id] = item
	return e.journal.save()
}
func (e *Engine) receipt(ctx context.Context, id string) error {
	item := e.journal.Items[id]
	if item.Ack {
		return nil
	}
	if time.Now().UnixMilli() >= item.Expires {
		item.Ack = true
		e.log.write("receipt_expired", id, "result_unknown", item.Count)
		return e.record(id, item)
	}
	_, err := e.api.call(ctx, "POST", "/api/wake/requests/"+id+"/result", map[string]string{"phase": item.Phase, "error_code": item.Error}, nil)
	if err != nil {
		var h HTTPError
		if errors.As(err, &h) && (h.Status == 404 || h.Status == 409 || h.Status == 410) {
			item.Ack = true
			e.log.write("receipt_rejected", id, h.Error(), item.Count)
			return e.record(id, item)
		}
		return err
	}
	item.Ack = true
	e.log.write("receipt_accepted", id, item.Phase, item.Count)
	return e.record(id, item)
}
func (e *Engine) recover(ctx context.Context) error {
	for id, item := range e.journal.Items {
		if item.Ack {
			continue
		}
		if item.Phase == "reserved" {
			item.Phase = "failed"
			item.Error = "execution_uncertain"
			if err := e.record(id, item); err != nil {
				return err
			}
			e.log.write("interrupted", id, item.Error, 0)
		}
		if err := e.receipt(ctx, id); err != nil {
			return err
		}
	}
	return nil
}

// Some platforms pause the monotonic clock during system sleep. Require both
// clocks to remain inside the permit; a wall-clock jump forward fails closed.
func withinDeadline(now, deadline time.Time) bool {
	return now.Before(deadline) && now.UnixMilli() < deadline.UnixMilli()
}

func (e *Engine) execute(ctx context.Context, job Job, pollStart time.Time) error {
	if !identifier.MatchString(job.ID) {
		return fault("invalid_job")
	}
	if item, ok := e.journal.Items[job.ID]; ok {
		if item.Phase == "reserved" {
			item.Phase = "failed"
			item.Error = "execution_uncertain"
			if err := e.record(job.ID, item); err != nil {
				return err
			}
		}
		return e.receipt(ctx, job.ID)
	}
	if job.RemainingMS <= 0 || job.RemainingMS > 30000 {
		return fault("invalid_job")
	}
	deadline := pollStart.Add(time.Duration(job.RemainingMS) * time.Millisecond)
	if !withinDeadline(time.Now(), deadline) {
		return fault("request_expired")
	}
	for id, item := range e.journal.Items {
		if item.Ack && time.Now().UnixMilli()-item.Expires > 7*24*60*60*1000 {
			delete(e.journal.Items, id)
		}
	}
	if len(e.journal.Items) >= 2048 {
		return fault("journal_full")
	}
	item := Entry{Expires: deadline.UnixMilli(), Phase: "reserved"}
	if err := e.record(job.ID, item); err != nil {
		return err
	}
	e.log.write("claimed", job.ID, "", 0)
	fail := func(code string) error {
		item.Phase = "failed"
		item.Error = code
		if err := e.record(job.ID, item); err != nil {
			return err
		}
		e.log.write("failed", job.ID, code, item.Count)
		return e.receipt(ctx, job.ID)
	}
	packet, err := magicPacket(job.MAC)
	if err != nil {
		return fail("invalid_mac")
	}
	if !job.SetupComplete {
		return fail("setup_incomplete")
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err = e.check(); err != nil {
		return fail("network_changed")
	}
	var permit struct {
		RemainingMS int64 `json:"remaining_ms"`
	}
	started := time.Now()
	_, err = e.api.call(ctx, "POST", "/api/wake/requests/"+job.ID+"/authorize-send", struct{}{}, &permit)
	if err != nil {
		// Even a lost authorization response must never be retried as a new send.
		item.Phase = "failed"
		item.Error = "authorization_uncertain"
		if saveErr := e.record(job.ID, item); saveErr != nil {
			return saveErr
		}
		e.log.write("failed", job.ID, item.Error, 0)
		return err
	}
	if permit.RemainingMS <= 0 || permit.RemainingMS > 2000 {
		return fail("invalid_permit")
	}
	lease := started.Add(time.Duration(permit.RemainingMS)*time.Millisecond - 50*time.Millisecond)
	if lease.Before(deadline) {
		deadline = lease
	}
	e.log.write("authorized", job.ID, "", 0)
	for i := 0; i < 3; i++ {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err = e.check(); err != nil {
			return fail("network_changed")
		}
		if !withinDeadline(time.Now(), deadline) {
			return fail("permit_expired")
		}
		if err = e.send(packet); err != nil {
			return fail("send_failed")
		}
		item.Count++
		e.log.write("packet_written", job.ID, "", item.Count)
		if i < 2 {
			timer := time.NewTimer(200 * time.Millisecond)
			select {
			case <-ctx.Done():
				timer.Stop()
				return ctx.Err()
			case <-timer.C:
			}
		}
	}
	item.Phase = "sent"
	if err = e.record(job.ID, item); err != nil {
		return err
	}
	e.log.write("sent", job.ID, "awaiting_app_heartbeat", item.Count)
	return e.receipt(ctx, job.ID)
}
