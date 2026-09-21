package main

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"syscall"
)

type Config struct {
	Origin    string `json:"server"`
	AgentID   string `json:"agent_id"`
	Token     string `json:"token"`
	Interface string `json:"interface"`
	CIDR      string `json:"ipv4_cidr"`
	Hardware  string `json:"interface_hardware"`
}

func netInterface(name string) (string, error) {
	i, err := net.InterfaceByName(name)
	if err != nil {
		return "", fault("invalid_interface")
	}
	return i.HardwareAddr.String(), nil
}
func broadcastFor(cidr string) (net.IP, error) {
	ip, network, err := net.ParseCIDR(cidr)
	if err != nil || ip.To4() == nil || !ip.IsPrivate() {
		return nil, fault("invalid_lan_cidr")
	}
	ones, bits := network.Mask.Size()
	if bits != 32 || ones < 8 || ones > 30 {
		return nil, fault("invalid_lan_cidr")
	}
	b := make(net.IP, 4)
	ip = ip.To4()
	for i := range b {
		b[i] = network.IP.To4()[i] | ^network.Mask[i]
	}
	if ip.Equal(network.IP) || ip.Equal(b) || !network.IP.IsPrivate() || !b.IsPrivate() {
		return nil, fault("invalid_lan_cidr")
	}
	return b, nil
}
func (c Config) checkNetwork() error {
	if _, err := broadcastFor(c.CIDR); err != nil {
		return err
	}
	iface, err := net.InterfaceByName(c.Interface)
	if err != nil || iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagBroadcast == 0 || iface.HardwareAddr.String() != c.Hardware || c.Hardware == "" {
		return fault("network_changed")
	}
	addrs, err := iface.Addrs()
	if err != nil {
		return fault("network_changed")
	}
	for _, a := range addrs {
		if a.String() == c.CIDR {
			return nil
		}
	}
	return fault("network_changed")
}
func (c Config) validate() error {
	if err := validOrigin(c.Origin); err != nil {
		return err
	}
	if !identifier.MatchString(c.AgentID) || len(c.Token) != 64 || !identifier.MatchString(c.Token) {
		return fault("invalid_credentials")
	}
	if len(c.Interface) > 64 || c.Interface == "" {
		return fault("invalid_interface")
	}
	_, err := broadcastFor(c.CIDR)
	return err
}
func privateDir(dir string) error {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return fault("storage_failed")
	}
	st, err := os.Lstat(dir)
	if err != nil || !st.IsDir() || st.Mode().Perm()&0077 != 0 {
		return fault("unsafe_state_directory")
	}
	if stat, ok := st.Sys().(*syscall.Stat_t); !ok || int(stat.Uid) != os.Geteuid() {
		return fault("unsafe_state_owner")
	}
	return nil
}
func lockDir(dir string) (*os.File, error) {
	path := filepath.Join(dir, "process.lock")
	fd, err := syscall.Open(path, syscall.O_CREAT|syscall.O_RDWR|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return nil, fault("unsafe_lock")
	}
	f := os.NewFile(uintptr(fd), path)
	if syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB) != nil {
		f.Close()
		return nil, fault("already_running")
	}
	return f, nil
}
func interfaces() error {
	list, err := net.Interfaces()
	if err != nil {
		return fault("network_unavailable")
	}
	fmt.Println("请明确选择电脑所在局域网的接口和 IPv4，不要选择 WAN、访客网或 VPN。")
	for _, i := range list {
		if i.Flags&net.FlagUp == 0 || i.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := i.Addrs()
		for _, a := range addrs {
			if _, err := broadcastFor(a.String()); err == nil {
				fmt.Printf("%s\t%s\n", i.Name, a.String())
			}
		}
	}
	return nil
}
