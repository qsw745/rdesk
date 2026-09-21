package main

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"net"
	"os"
)

type AppNetwork struct {
	Interface string `json:"interface"`
	CIDR      string `json:"ipv4_cidr"`
	Hardware  string `json:"interface_hardware"`
}

func appNetworks() ([]AppNetwork, error) {
	list, err := net.Interfaces()
	if err != nil {
		return nil, fault("network_unavailable")
	}
	result := []AppNetwork{}
	for _, i := range list {
		if i.Flags&net.FlagUp == 0 || i.Flags&net.FlagBroadcast == 0 || i.Flags&net.FlagLoopback != 0 || len(i.HardwareAddr) != 6 {
			continue
		}
		addresses, _ := i.Addrs()
		for _, a := range addresses {
			if _, err := broadcastFor(a.String()); err == nil {
				result = append(result, AppNetwork{i.Name, a.String(), i.HardwareAddr.String()})
			}
		}
	}
	return result, nil
}

// App owns the process. A lost stdin pipe cancels pending work on parent exit.
// Credentials travel only over stdin and remain in memory; journal is durable.
func appRun(ctx context.Context, dir string, input io.Reader) error {
	reader := bufio.NewReader(io.LimitReader(input, 16385))
	raw, err := reader.ReadBytes('\n')
	if err != nil || len(raw) > 8192 {
		return fault("invalid_config")
	}
	var c Config
	if json.Unmarshal(raw, &c) != nil {
		return fault("invalid_config")
	}
	if err = c.validate(); err != nil {
		return err
	}
	if err = c.checkNetwork(); err != nil {
		return err
	}
	owned, cancel := context.WithCancel(ctx)
	defer cancel()
	go func() { _, _ = io.Copy(io.Discard, reader); cancel() }()
	return run(owned, dir, c)
}
func printAppNetworks() error {
	list, err := appNetworks()
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(list)
}
