package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestPacket(t *testing.T) {
	p, err := magicPacket("02:11:22:33:44:55")
	if err != nil || len(p) != 102 || !bytes.Equal(p[:6], bytes.Repeat([]byte{255}, 6)) {
		t.Fatal("invalid magic packet")
	}
	for i := 0; i < 16; i++ {
		if !bytes.Equal(p[6+i*6:12+i*6], []byte{2, 17, 34, 51, 68, 85}) {
			t.Fatal("incorrect MAC repetition")
		}
	}
	for _, v := range []string{"00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff", "01:11:22:33:44:55", "bad"} {
		if _, err := magicPacket(v); err == nil {
			t.Fatal("accepted", v)
		}
	}
}

func TestTransportRejectsRedirectAndLargeResponse(t *testing.T) {
	secret := "secret-must-not-leak"
	reached := false
	sink := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { reached = true }))
	defer sink.Close()
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/redirect" {
			http.Redirect(w, r, sink.URL, 307)
			return
		}
		w.Write(bytes.Repeat([]byte("x"), 65537))
	}))
	defer server.Close()
	api := newAPI(server.URL, secret)
	api.client.Transport = server.Client().Transport
	for _, path := range []string{"/redirect", "/large"} {
		if _, err := api.call(context.Background(), "GET", path, nil, nil); err == nil {
			t.Fatal("accepted", path)
		}
	}
	if reached {
		t.Fatal("redirect followed")
	}
	for _, origin := range []string{"http://example.com", "https://user:pass@example.com", "https://example.com/path", "https://example.com?x=1"} {
		if validOrigin(origin) == nil {
			t.Fatal("unsafe origin", origin)
		}
	}
}

// A real TLS fake server, a durable journal and an injected packet sink exercise
// the same execution path as the daemon, without waking physical hardware.
func TestExecutionAndLostReceiptNeverResend(t *testing.T) {
	auth, sends, receipts := 0, 0, 0
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/wake/requests/job/authorize-send":
			auth++
			json.NewEncoder(w).Encode(map[string]int{"remaining_ms": 2000})
		case "/api/wake/requests/job/result":
			receipts++
			if receipts == 1 {
				w.WriteHeader(503)
				return
			}
			w.Write([]byte(`{}`))
		default:
			t.Errorf("unexpected path %s", r.URL.Path)
		}
	}))
	defer server.Close()
	dir := t.TempDir()
	api := newAPI(server.URL, "token")
	api.client.Transport = server.Client().Transport
	e := testEngine(t, dir, api, func([]byte) error { sends++; return nil })
	job := Job{ID: "job", MAC: "02:11:22:33:44:55", RemainingMS: 30000, SetupComplete: true}
	if err := e.execute(context.Background(), job, time.Now()); err == nil {
		t.Fatal("expected lost receipt")
	}
	e = testEngine(t, dir, api, func([]byte) error { sends++; return nil }) // process restart
	if err := e.recover(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := e.execute(context.Background(), job, time.Now()); err != nil {
		t.Fatal(err)
	}
	if auth != 1 || sends != 3 || receipts != 2 {
		t.Fatalf("auth=%d sends=%d receipts=%d", auth, sends, receipts)
	}
}

func TestExpiredLeaseAndNetworkChangeDoNotSend(t *testing.T) {
	for _, reason := range []string{"lease", "network", "cancel", "reserved"} {
		t.Run(reason, func(t *testing.T) {
			sends := 0
			server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/api/wake/requests/job/authorize-send" {
					lease := 2000
					if reason == "lease" {
						time.Sleep(80 * time.Millisecond)
						lease = 20
					}
					json.NewEncoder(w).Encode(map[string]int{"remaining_ms": lease})
					return
				}
				w.Write([]byte(`{}`))
			}))
			defer server.Close()
			api := newAPI(server.URL, "token")
			api.client.Transport = server.Client().Transport
			dir := t.TempDir()
			e := testEngine(t, dir, api, func([]byte) error { sends++; return nil })
			if reason == "network" {
				e.check = func() error { return fault("network_changed") }
			}
			if reason == "reserved" {
				e.journal.Items["job"] = Entry{Expires: time.Now().Add(time.Second * 30).UnixMilli(), Phase: "reserved"}
				e.journal.save()
			}
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			if reason == "cancel" {
				cancel()
			}
			_ = e.execute(ctx, Job{ID: "job", MAC: "02:11:22:33:44:55", RemainingMS: 30000, SetupComplete: true}, time.Now())
			if sends != 0 {
				t.Fatal("unsafe send", sends)
			}
		})
	}
}

func TestJournalCorruptionFailsClosedAndPrivate(t *testing.T) {
	dir := t.TempDir()
	j, err := loadJournal(dir)
	if err != nil {
		t.Fatal(err)
	}
	j.Items["job"] = Entry{Phase: "reserved"}
	if err := j.save(); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(filepath.Join(dir, "journal.json"))
	if info.Mode().Perm() != 0600 {
		t.Fatal("permissions")
	}
	os.WriteFile(filepath.Join(dir, "journal.json"), []byte("broken"), 0600)
	if _, err := loadJournal(dir); err == nil {
		t.Fatal("corrupt journal silently reset")
	}
}

func TestAmbiguousAuthorizationAndPartialSendNeverReplay(t *testing.T) {
	for _, scenario := range []string{"lost_authorization", "cancel_after_first_packet"} {
		t.Run(scenario, func(t *testing.T) {
			auth, sends, receipts := 0, 0, 0
			server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/api/wake/requests/job/authorize-send" {
					auth++
					if scenario == "lost_authorization" {
						connection, _, err := w.(http.Hijacker).Hijack()
						if err != nil {
							t.Error(err)
							return
						}
						connection.Close()
						return
					}
					w.Write([]byte(`{"remaining_ms":2000}`))
					return
				}
				if r.URL.Path == "/api/wake/requests/job/result" {
					receipts++
					var result map[string]string
					json.NewDecoder(r.Body).Decode(&result)
					if result["phase"] != "failed" {
						t.Error("uncertain result must not become sent")
					}
					w.Write([]byte(`{}`))
					return
				}
				t.Error("unexpected route")
			}))
			defer server.Close()
			api := newAPI(server.URL, "token")
			api.client.Transport = server.Client().Transport
			dir := t.TempDir()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			e := testEngine(t, dir, api, func([]byte) error { sends++; cancel(); return nil })
			job := Job{ID: "job", MAC: "02:11:22:33:44:55", RemainingMS: 30000, SetupComplete: true}
			if err := e.execute(ctx, job, time.Now()); err == nil {
				t.Fatal("expected interrupted exchange")
			}
			e = testEngine(t, dir, api, func([]byte) error { t.Fatal("replayed"); return nil })
			if err := e.recover(context.Background()); err != nil {
				t.Fatal(err)
			}
			if err := e.execute(context.Background(), job, time.Now()); err != nil {
				t.Fatal(err)
			}
			expected := 0
			if scenario == "cancel_after_first_packet" {
				expected = 1
			}
			if auth != 1 || sends != expected || receipts != 1 {
				t.Fatalf("auth=%d sends=%d receipts=%d", auth, sends, receipts)
			}
		})
	}
}

func testEngine(t *testing.T, dir string, api *API, send func([]byte) error) *Engine {
	t.Helper()
	j, err := loadJournal(dir)
	if err != nil {
		t.Fatal(err)
	}
	return &Engine{api: api, journal: j, check: func() error { return nil }, send: send, log: &EventLog{dir: dir}}
}
