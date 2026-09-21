package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestAppRejectsInvalidInput(t *testing.T) {
	for _, raw := range []string{"", "{}\n", strings.Repeat("x", 9000) + "\n", `{"server":"http://unsafe","agent_id":"id"}` + "\n"} {
		if appRun(context.Background(), t.TempDir(), strings.NewReader(raw)) == nil {
			t.Fatal("accepted bad config")
		}
	}
}
func TestAppNetworksContainOnlyBroadcastLAN(t *testing.T) {
	networks, err := appNetworks()
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range networks {
		if _, err := broadcastFor(n.CIDR); err != nil || n.Hardware == "" {
			t.Fatal(n)
		}
	}
}

func TestAppParentExitStopsHelper(t *testing.T) {
	networks, err := appNetworks()
	if err != nil || len(networks) == 0 {
		t.Skip("no broadcast LAN")
	}
	n := networks[0]
	c := Config{Origin: "https://127.0.0.1:1", AgentID: "test", Token: strings.Repeat("a", 64), Interface: n.Interface, CIDR: n.CIDR, Hardware: n.Hardware}
	raw, _ := json.Marshal(c)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	// EOF immediately after configuration simulates app termination. No WOL job exists.
	start := time.Now()
	err = appRun(ctx, t.TempDir(), strings.NewReader(string(raw)+"\n"))
	if err != nil {
		t.Fatal(err)
	}
	if time.Since(start) > time.Second {
		t.Fatal("child outlived parent")
	}
}

func TestPermitClockBoundaries(t *testing.T) {
	now := time.Now()
	deadline := now.Add(time.Second)
	if !withinDeadline(now, deadline) {
		t.Fatal("valid permit rejected")
	}
	if withinDeadline(deadline, deadline) || withinDeadline(deadline.Add(time.Nanosecond), deadline) {
		t.Fatal("expired permit accepted")
	}
	// Check an expired wall-clock value. This does not simulate a live system sleep.
	wallAfterResume := time.UnixMilli(deadline.UnixMilli() + 3600000)
	if withinDeadline(wallAfterResume, deadline) {
		t.Fatal("resume accepted old permit")
	}
}
