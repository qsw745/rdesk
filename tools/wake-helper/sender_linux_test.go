package main

import (
	"net"
	"os"
	"testing"
	"time"
)

// Opt-in, isolated Docker network only; never runs on the user's home LAN.
func TestLinuxInterfaceBoundBroadcast(t *testing.T) {
	if os.Getenv("RDESK_ISOLATED_BROADCAST_TEST") != "1" {
		t.Skip("isolated local container required")
	}
	iface, err := net.InterfaceByName("eth0")
	if err != nil {
		t.Fatal(err)
	}
	addrs, _ := iface.Addrs()
	var cidr string
	for _, a := range addrs {
		if _, err := broadcastFor(a.String()); err == nil {
			cidr = a.String()
			break
		}
	}
	cfg := Config{Interface: "eth0", CIDR: cidr, Hardware: iface.HardwareAddr.String()}
	sink, err := net.ListenPacket("udp4", "0.0.0.0:9")
	if err != nil {
		t.Fatal(err)
	}
	defer sink.Close()
	send, closeFn, err := packetSender(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer closeFn()
	expected, _ := magicPacket("02:11:22:33:44:55")
	if err := send(expected); err != nil {
		t.Fatal(err)
	}
	sink.SetReadDeadline(time.Now().Add(time.Second))
	b := make([]byte, 200)
	n, from, err := sink.ReadFrom(b)
	if err != nil || n != 102 || string(b[:n]) != string(expected) {
		t.Fatal("broadcast", n, err)
	}
	ip, _, _ := net.ParseCIDR(cidr)
	if from.(*net.UDPAddr).IP.String() != ip.String() {
		t.Fatal("wrong source interface")
	}
}
