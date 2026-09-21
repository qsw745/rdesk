package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestRealRDeskProtocol(t *testing.T) {
	binary := os.Getenv("RDESK_TEST_SERVER_BINARY")
	if binary == "" {
		t.Skip("set RDESK_TEST_SERVER_BINARY to a locally built server")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	_, port, _ := net.SplitHostPort(address)
	listener.Close()
	dir := t.TempDir()
	cmd := exec.Command(binary, "--host", "127.0.0.1", "--signaling-port", port, "--user-store-path", filepath.Join(dir, "users.json"))
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { cmd.Process.Kill(); cmd.Wait() }()
	base, _ := url.Parse("http://" + address)
	proxy := httputil.NewSingleHostReverseProxy(base)
	proxy.ErrorLog = log.New(io.Discard, "", 0) // Expected while the child starts.
	tls := httptest.NewTLSServer(proxy)
	defer tls.Close()
	api := newAPI(tls.URL, "")
	api.client.Transport = tls.Client().Transport
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	ready := false
	for i := 0; i < 100; i++ {
		if _, err := api.call(ctx, "GET", "/health", nil, nil); err == nil {
			ready = true
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !ready {
		t.Fatal("local server did not start")
	}
	var account struct {
		Token string `json:"token"`
	}
	if _, err := api.call(ctx, "POST", "/api/account/register", map[string]string{"username": "local-helper-test", "password": "local-ephemeral-password"}, &account); err != nil {
		t.Fatal(err)
	}
	api.token = account.Token
	var agent struct{ ID, Token string }
	if _, err := api.call(ctx, "POST", "/api/wake/agents", map[string]string{"name": "本地测试助手"}, &agent); err != nil {
		t.Fatal(err)
	}
	var target struct{ ID, Token string }
	if _, err := api.call(ctx, "POST", "/api/wake/targets", map[string]string{"name": "模拟电脑", "mac": "02:11:22:33:44:55", "device_id": "local-test-pc", "agent_id": agent.ID}, &target); err != nil {
		t.Fatal(err)
	}
	helper := newAPI(tls.URL, agent.Token)
	helper.client.Transport = tls.Client().Transport
	jobs := make(chan Job, 1)
	pollErrors := make(chan error, 1)
	start := time.Now()
	go func() {
		var job Job
		_, err := helper.call(ctx, "POST", "/api/wake/agents/"+agent.ID+"/poll", struct{}{}, &job)
		if err != nil {
			pollErrors <- err
			return
		}
		jobs <- job
	}()
	// Wait for the actual registered poll heartbeat, not a timing-only assumption.
	for i := 0; i < 100; i++ {
		var online struct{ Agents []struct{ Online bool } }
		api.call(ctx, "GET", "/api/wake/agents", nil, &online)
		if len(online.Agents) == 1 && online.Agents[0].Online {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	var request DiagnosticRequest
	if _, err := api.call(ctx, "POST", "/api/wake/requests", map[string]string{"target_id": target.ID}, &request); err != nil {
		t.Fatal(err)
	}
	var job Job
	select {
	case job = <-jobs:
	case err := <-pollErrors:
		t.Fatal(err)
	case <-ctx.Done():
		t.Fatal("poll timeout")
	}
	sink, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer sink.Close()
	source, err := net.Dial("udp4", sink.LocalAddr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	e := testEngine(t, t.TempDir(), helper, func(b []byte) error { _, err := source.Write(b); return err })
	if err := e.execute(ctx, job, start); err != nil {
		t.Fatal(err)
	}
	if item := e.journal.Items[job.ID]; item.Phase != "sent" {
		t.Fatalf("execution phase=%s error=%s packets=%d", item.Phase, item.Error, item.Count)
	}
	for i := 0; i < 3; i++ {
		sink.SetReadDeadline(time.Now().Add(time.Second))
		packet := make([]byte, 200)
		n, _, err := sink.ReadFrom(packet)
		if err != nil || n != 102 {
			t.Fatal("packet reception", n, err)
		}
	}
	if _, err := api.call(ctx, "GET", "/api/wake/requests/"+job.ID, nil, &request); err != nil || request.Phase != "sent" {
		t.Fatal("sent receipt", err, request.Phase)
	}
	pc := newAPI(tls.URL, target.Token)
	pc.client.Transport = tls.Client().Transport
	if _, err := pc.call(ctx, "POST", "/api/wake/targets/"+target.ID+"/heartbeat", struct{}{}, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := api.call(ctx, "GET", "/api/wake/requests/"+job.ID, nil, &request); err != nil || request.Phase != "online" {
		t.Fatal("heartbeat", err, request.Phase)
	}
	if err := diagnose(ctx, api, target.ID, io.Discard); err != nil {
		t.Fatal(err)
	}
	e = testEngine(t, e.journal.dir, helper, func([]byte) error { t.Fatal("replayed after restart"); return nil })
	if err := e.recover(ctx); err != nil {
		t.Fatal(err)
	}
	if err := e.execute(ctx, job, time.Now()); err != nil {
		t.Fatal(err)
	}
}

func TestDiagnosticRedactionAndTimeline(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/wake/targets" {
			w.Write([]byte(`{"targets":[{"id":"pc","name":"电脑","mac":"secret-mac","token":"secret-token"}]}`))
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"requests": []any{map[string]any{"id": "job", "phase": "unconfirmed", "authorized_at_ms": 1000, "token": "secret-token"}}})
	}))
	defer srv.Close()
	api := newAPI(srv.URL, "account-secret")
	api.client.Transport = srv.Client().Transport
	writer := &captureWriter{}
	if err := diagnose(context.Background(), api, "pc", writer); err != nil {
		t.Fatal(err)
	}
	if bytesContains(writer.data, []byte("secret")) || !bytesContains(writer.data, []byte("授权：")) {
		t.Fatal("diagnostic privacy or timeline")
	}
}

type captureWriter struct{ data []byte }

func (w *captureWriter) Write(b []byte) (int, error) {
	w.data = append(w.data, b...)
	return len(b), nil
}
func bytesContains(b, s []byte) bool {
	for i := 0; i+len(s) <= len(b); i++ {
		if string(b[i:i+len(s)]) == string(s) {
			return true
		}
	}
	return false
}
