package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"math/rand/v2"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const version = "0.1.0"

func main() {
	if err := command(os.Args[1:]); err != nil {
		// Return codes, never raw HTTP/OS errors that may contain credentials.
		code := safeError(err)
		fmt.Fprintln(os.Stderr, "未完成："+code+"。"+explain("failed", code))
		os.Exit(1)
	}
}
func safeError(err error) string {
	var f fault
	var h HTTPError
	if errors.As(err, &f) {
		return string(f)
	}
	if errors.As(err, &h) {
		return h.Error()
	}
	if errors.Is(err, context.Canceled) {
		return "cancelled"
	}
	return "operation_failed"
}
func command(args []string) error {
	if len(args) == 0 {
		fmt.Println("RDesk 局域网开机助手 " + version + "\n命令：interfaces / enroll / run / inspect / diagnose / version\n详情见 docs/lan-wake-helper.md")
		return nil
	}
	if args[0] == "version" {
		fmt.Println(version)
		return nil
	}
	if args[0] == "app-networks" {
		return printAppNetworks()
	}
	if args[0] == "interfaces" {
		return interfaces()
	}
	fs := flag.NewFlagSet(args[0], flag.ContinueOnError)
	dir := fs.String("state", "./rdesk-wake-state", "私有配置与日志目录")
	origin := fs.String("server", "https://qisw.top", "HTTPS 服务地址")
	name := fs.String("name", "家中局域网助手", "助手名称")
	iface := fs.String("interface", "", "电脑所在 LAN 接口")
	cidr := fs.String("cidr", "", "助手本机的 IPv4 CIDR")
	target := fs.String("target", "", "只诊断指定电脑的 target ID（可选）")
	if err := fs.Parse(args[1:]); err != nil {
		return fault("invalid_arguments")
	}
	if fs.NArg() != 0 {
		return fault("invalid_arguments")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if args[0] == "diagnose" {
		api, err := accountLogin(ctx, strings.TrimRight(*origin, "/"))
		if err != nil {
			return err
		}
		return diagnose(ctx, api, *target, os.Stdout)
	}
	if args[0] != "enroll" && args[0] != "run" && args[0] != "inspect" && args[0] != "app-run" {
		return fault("unknown_command")
	}
	if err := privateDir(*dir); err != nil {
		return err
	}
	if args[0] == "inspect" {
		return inspect(*dir)
	}
	lock, err := lockDir(*dir)
	if err != nil {
		return err
	}
	defer lock.Close()
	if args[0] == "app-run" {
		return appRun(ctx, *dir, os.Stdin)
	}
	if args[0] == "enroll" {
		return enroll(ctx, *dir, strings.TrimRight(*origin, "/"), *name, *iface, *cidr)
	}
	raw, err := readPrivate(filepath.Join(*dir, "config.json"), 8192)
	if err != nil {
		return fault("config_unreadable")
	}
	var config Config
	if json.Unmarshal(raw, &config) != nil {
		return fault("invalid_config")
	}
	if err = config.validate(); err != nil {
		return err
	}
	return run(ctx, *dir, config)
}
func accountLogin(ctx context.Context, origin string) (*API, error) {
	if err := validOrigin(origin); err != nil {
		return nil, err
	}
	var credentials struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	raw, err := io.ReadAll(io.LimitReader(os.Stdin, 4097))
	if err != nil || len(raw) > 4096 || json.Unmarshal(raw, &credentials) != nil || credentials.Username == "" || credentials.Password == "" {
		return nil, fault("credentials_stdin_required")
	}
	api := newAPI(origin, "")
	var session struct {
		Token string `json:"token"`
	}
	_, err = api.call(ctx, "POST", "/api/account/login", credentials, &session)
	if err != nil {
		return nil, err
	}
	if !identifier.MatchString(session.Token) {
		return nil, fault("invalid_response")
	}
	api.token = session.Token
	return api, nil
}
func enroll(ctx context.Context, dir, origin, name, iface, cidr string) error {
	if _, err := os.Lstat(filepath.Join(dir, "config.json")); !errors.Is(err, os.ErrNotExist) {
		return fault("config_already_exists")
	}
	network, err := netInterface(iface)
	if err != nil {
		return err
	}
	c := Config{Origin: origin, Interface: iface, CIDR: cidr, Hardware: network}
	if err = c.checkNetwork(); err != nil {
		return err
	}
	if len([]rune(name)) < 1 || len([]rune(name)) > 80 {
		return fault("invalid_name")
	}
	api, err := accountLogin(ctx, origin)
	if err != nil {
		return err
	}
	var created struct {
		ID    string `json:"id"`
		Token string `json:"token"`
	}
	if _, err = api.call(ctx, "POST", "/api/wake/agents", map[string]string{"name": name}, &created); err != nil {
		return err
	}
	c.AgentID = created.ID
	c.Token = created.Token
	if err = c.validate(); err != nil {
		return err
	}
	if err = atomicJSON(dir, "config.json", c); err != nil {
		_, rollback := api.call(ctx, "DELETE", "/api/wake/agents/"+c.AgentID, nil, nil)
		if rollback != nil {
			return fault("enrollment_cleanup_required")
		}
		return err
	}
	fmt.Println("助手已登记。请在这台 Linux 设备启动 run，再在 RDesk 的电脑配置中选择该助手。")
	fmt.Println("尚未发出任何唤醒包，也没有验证电脑开机。")
	return nil
}
func run(ctx context.Context, dir string, c Config) error {
	journal, err := loadJournal(dir)
	if err != nil {
		return err
	}
	send, closeSender, err := packetSender(c)
	if err != nil {
		return err
	}
	defer closeSender()
	log := &EventLog{dir: dir}
	engine := &Engine{api: newAPI(c.Origin, c.Token), journal: journal, send: send, check: c.checkNetwork, log: log}
	log.write("started", "", "", 0)
	defer log.write("stopped", "", "", 0)
	fmt.Println("开机助手运行中。诊断保存在私有目录 events.jsonl；Ctrl+C 停止。")
	failures := 0
	lastHealth := time.Now()
	for ctx.Err() == nil {
		if err = c.checkNetwork(); err != nil {
			log.write("network_changed", "", "network_changed", 0)
			return err
		}
		err = engine.recover(ctx)
		if err == nil {
			var job Job
			start := time.Now()
			var status int
			status, err = engine.api.call(ctx, "POST", "/api/wake/agents/"+c.AgentID+"/poll", struct{}{}, &job)
			if err == nil && status != 204 {
				err = engine.execute(ctx, job, start)
			}
		}
		if ctx.Err() != nil {
			return nil
		}
		if err == nil {
			if failures > 0 {
				log.write("connection_restored", "", "", 0)
			}
			if time.Since(lastHealth) > 5*time.Minute {
				log.write("poll_healthy", "", "", 0)
				lastHealth = time.Now()
			}
			failures = 0
			// Also protects against a misconfigured server returning immediate 204s.
			if !wait(ctx, 250*time.Millisecond) {
				return nil
			}
			continue
		}
		code := safeError(err)
		log.write("poll_or_result_failed", "", code, 0)
		var h HTTPError
		if errors.As(err, &h) && (h.Status == 401 || h.Status == 403 || h.Status == 404) {
			return err
		}
		if code == "storage_failed" || code == "journal_full" || code == "unsafe_private_file" {
			return err
		}
		failures++
		n := failures
		if n > 4 {
			n = 4
		}
		delay := time.Duration(1<<n)*time.Second + time.Duration(rand.IntN(1000))*time.Millisecond
		if !wait(ctx, delay) {
			return nil
		}
	}
	return nil
}
func wait(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}
