package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNetworkConfiguration(t *testing.T) {
	for _, cidr := range []string{"192.168.31.1/24", "10.10.1.20/16"} {
		b, err := broadcastFor(cidr)
		if err != nil || !strings.HasSuffix(b.String(), ".255") {
			t.Fatal(cidr, err)
		}
	}
	for _, cidr := range []string{"0.0.0.0/0", "127.0.0.1/8", "192.168.31.255/24", "192.168.31.0/24", "192.168.31.1/32", "192.168.31.1/8", "172.16.1.1/8", "224.1.1.1/24", "8.8.8.8/24", "fe80::1/64"} {
		if _, err := broadcastFor(cidr); err == nil {
			t.Fatal("unsafe network", cidr)
		}
	}
}

func TestPrivateStateAndExclusiveLock(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "private")
	if err := privateDir(dir); err != nil {
		t.Fatal(err)
	}
	f, err := lockDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err := lockDir(dir); err == nil {
		t.Fatal("second daemon allowed")
	}
	unsafe := filepath.Join(t.TempDir(), "world-readable")
	os.Mkdir(unsafe, 0755)
	if privateDir(unsafe) == nil {
		t.Fatal("accepted public state")
	}
	link := filepath.Join(t.TempDir(), "link")
	os.Symlink(dir, link)
	if privateDir(link) == nil {
		t.Fatal("accepted symlink")
	}
}

func TestDiagnosticMeaning(t *testing.T) {
	for _, phase := range []string{"queued", "claimed", "sent", "online", "unconfirmed", "failed", "expired", "interrupted"} {
		if explain(phase, "") == "" {
			t.Fatal("missing phase", phase)
		}
	}
	if !strings.Contains(explain("unconfirmed", ""), "登录") {
		t.Fatal("must distinguish app heartbeat from hardware power")
	}
	if !strings.Contains(explain("failed", "network_changed"), "网络") {
		t.Fatal("missing actionable error")
	}
}
