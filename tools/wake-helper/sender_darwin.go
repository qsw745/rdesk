package main

import (
	"context"
	"net"
	"syscall"
	"time"
)

func packetSender(c Config) (func([]byte) error, func(), error) {
	if err := c.checkNetwork(); err != nil {
		return nil, nil, err
	}
	iface, err := net.InterfaceByName(c.Interface)
	if err != nil {
		return nil, nil, fault("network_changed")
	}
	ip, _, _ := net.ParseCIDR(c.CIDR)
	broadcast, _ := broadcastFor(c.CIDR)
	lc := net.ListenConfig{Control: func(_, _ string, raw syscall.RawConn) error {
		var setErr error
		err := raw.Control(func(fd uintptr) {
			setErr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_BROADCAST, 1)
			if setErr == nil {
				setErr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IP, syscall.IP_BOUND_IF, iface.Index)
			}
		})
		if err != nil {
			return err
		}
		return setErr
	}}
	conn, err := lc.ListenPacket(context.Background(), "udp4", net.JoinHostPort(ip.String(), "0"))
	if err != nil {
		return nil, nil, fault("cannot_bind_lan_interface")
	}
	destination := &net.UDPAddr{IP: broadcast, Port: 9}
	return func(b []byte) error {
		if err := conn.SetWriteDeadline(time.Now().Add(50 * time.Millisecond)); err != nil {
			return fault("send_failed")
		}
		n, err := conn.WriteTo(b, destination)
		if err != nil || n != len(b) {
			return fault("send_failed")
		}
		return nil
	}, func() { _ = conn.Close() }, nil
}
