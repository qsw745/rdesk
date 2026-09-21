//go:build !linux

package main

func packetSender(Config) (func([]byte) error, func(), error) {
	return nil, nil, fault("daemon_requires_linux")
}
