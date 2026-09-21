package main

import (
	"net"
	"os"
	"testing"
	"time"
)

// Explicit local diagnostic: payload is plain text, never a WOL magic packet.
func TestDarwinBoundBroadcastProbe(t *testing.T) {
	if os.Getenv("RDESK_LOCAL_BROADCAST_PROBE") != "1" {
		t.Skip("local opt-in probe")
	}
	networks, err := appNetworks()
	if err != nil || len(networks) == 0 {
		t.Fatal("no LAN")
	}
	n := networks[0]
	cfg := Config{Interface: n.Interface, CIDR: n.CIDR, Hardware: n.Hardware}
	sink, err := net.ListenPacket("udp4", "0.0.0.0:9")
	if err != nil {
		t.Fatal(err)
	}
	defer sink.Close()
	send, closeSender, err := packetSender(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer closeSender()
	payload := []byte("RDesk local connectivity probe; NOT a magic packet")
	if err = send(payload); err != nil {
		t.Fatal(err)
	}
	sink.SetReadDeadline(time.Now().Add(time.Second))
	b := make([]byte, 512)
	count, from, err := sink.ReadFrom(b)
	if err != nil || string(b[:count]) != string(payload) {
		t.Fatal("probe not received", err)
	}
	ip, _, _ := net.ParseCIDR(n.CIDR)
	if !from.(*net.UDPAddr).IP.Equal(ip) {
		t.Fatal("incorrect source interface")
	}
}
