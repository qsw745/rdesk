package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode"
)

func explain(phase, code string) string {
	errors := map[string]string{
		"network_changed":             "助手的局域网接口或地址已变化。检查所选 LAN 和固定地址后重新配置；没有自动切换其他网络。",
		"network_or_tls":              "助手到服务的网络或证书校验失败。检查联网、DNS、系统时间和 CA 证书；恢复网络后会退避重连。",
		"permit_expired":              "发送授权在发包前或三次发送中途过期。查看本地发包计数；不要把此状态当作绝对未发包。",
		"request_expired":             "请求已超过发送期限，未开始新的发送。请恢复连接后重新发起。",
		"authorization_uncertain":     "未能确认发送授权。本助手不再执行这条请求，请查看回执后重新发起。",
		"execution_uncertain":         "助手执行期间中断，不能确认是否已经发过包。为避免重复操作，不自动重发。",
		"send_failed":                 "向局域网写入唤醒包失败或仅完成部分发送。检查接口权限和本地发包计数。",
		"setup_incomplete":            "电脑配置尚未完成，请在 App 内完成助手和 BIOS 确认。",
		"server_restarted":            "服务器重启后旧请求已中断，请重新发起。",
		"http_401":                    "登录或助手授权已失效，也可能已被停用。检查 App 中助手状态，重新登记前先移除失效助手。",
		"http_403":                    "服务器拒绝该身份执行操作。检查账号和助手归属。",
		"http_404":                    "服务器没有该接口或资源，请确认服务地址和版本。",
		"http_429":                    "请求过于频繁，请等待后重试。",
		"storage_failed":              "本地记录无法可靠保存，已停止执行以避免重复发包。检查空间、权限和磁盘。",
		"journal_corrupt":             "去重记录损坏，已拒绝运行。保留日志排查，不要在有未完成请求时清空记录重试。",
		"journal_full":                "本地去重记录达到上限，暂停执行。最近七天内的记录不会为新请求被强制覆盖。",
		"already_running":             "该配置目录已有助手进程运行。不要并行启动第二个实例。",
		"cannot_bind_lan_interface":   "无法绑定 LAN 网卡。Linux 需要相应网络权限（root 或 CAP_NET_RAW），并且接口必须在线。",
		"daemon_requires_linux":       "此平台只提供登记与诊断命令；发送助手须运行在支持的 Linux 设备。",
		"credentials_stdin_required":  "请通过随附的安全输入脚本传入账号，不要把密码放在命令参数中。",
		"config_already_exists":       "该目录已有登记配置。保留去重记录；更换助手前先在 App 停用旧助手。",
		"enrollment_cleanup_required": "本地保存失败且未能撤销登记，请到 App 助手管理移除刚创建的助手。",
	}
	if text, ok := errors[code]; ok {
		return text
	}
	phases := map[string]string{
		"queued":      "服务器已收到请求，尚未被家中助手领取。检查助手是否持续在线。",
		"claimed":     "助手已领取，尚无成功发送回执。结合授权时间和助手日志区分授权、发包或回执故障。",
		"sent":        "助手报告已发送唤醒包，正在等待电脑应用上线。这不证明硬件已经开机。",
		"online":      "请求后收到电脑应用的新心跳。若电脑原本在线或人工启动，这也不能单独证明是唤醒包导致开机。",
		"unconfirmed": "观察期内未收到电脑应用心跳。电脑可能已经开机但仍在登录界面；确认 Windows 登录和 RDesk 自启动，再检查网卡供电与 BIOS。",
		"expired":     "请求过期，没有成功发送回执；若已领取，仍需查看助手本地日志确认是否部分发送或回执丢失。",
		"failed":      "本次执行失败，查看诊断代码及助手本地日志定位。",
		"cancelled":   "配置或助手发生变化，本次请求已取消。",
		"interrupted": "服务或任务中断，旧请求不会自动重发。",
	}
	if text, ok := phases[phase]; ok {
		return text
	}
	return "暂无足够诊断信息，不能判断电脑是否开机。"
}
func clean(s string) string {
	out := []rune{}
	for _, r := range s {
		if !unicode.IsControl(r) && !unicode.Is(unicode.Cf, r) {
			out = append(out, r)
		}
		if len(out) >= 160 {
			break
		}
	}
	return string(out)
}
func stamp(ms int64) string {
	if ms <= 0 {
		return "未记录"
	}
	return time.UnixMilli(ms).Local().Format("2006-01-02 15:04:05.000 -07:00")
}

type DiagnosticRequest struct {
	ID         string `json:"id"`
	Phase      string `json:"phase"`
	Created    int64  `json:"created_at_ms"`
	Claimed    int64  `json:"claimed_at_ms"`
	Authorized int64  `json:"authorized_at_ms"`
	Sent       int64  `json:"sent_at_ms"`
	Online     int64  `json:"online_at_ms"`
	Expires    int64  `json:"expires_at_ms"`
	Observe    int64  `json:"observe_until_ms"`
	Error      string `json:"error_code"`
}

func diagnose(ctx context.Context, api *API, target string, out io.Writer) error {
	if target != "" && !identifier.MatchString(target) {
		return fault("invalid_target")
	}
	var targets struct {
		Targets []struct {
			ID          string `json:"id"`
			Name        string `json:"name"`
			Online      bool   `json:"online"`
			AgentOnline bool   `json:"agent_online"`
			LastSeen    int64  `json:"last_seen_ms"`
		}
	}
	if _, err := api.call(ctx, "GET", "/api/wake/targets", nil, &targets); err != nil {
		return err
	}
	if len(targets.Targets) > 20 {
		return fault("invalid_response")
	}
	fmt.Fprintln(out, "RDesk 远程开机诊断 · "+time.Now().Format(time.RFC3339))
	fmt.Fprintln(out, "只读报告，不发出开机指令。密码、令牌、MAC 和局域网地址不包含在此报告中。")
	fmt.Fprintln(out, "线上记录保留最近 7 天、每账号最多 50 条；无记录不等于从未请求。")
	found := false
	for _, t := range targets.Targets {
		if target != "" && target != t.ID {
			continue
		}
		if !identifier.MatchString(t.ID) {
			return fault("invalid_response")
		}
		found = true
		fmt.Fprintf(out, "\n电脑：%s\n配置 ID：%s\n助手在线：%t；电脑应用在线：%t；最近心跳：%s\n", clean(t.Name), t.ID, t.AgentOnline, t.Online, stamp(t.LastSeen))
		var history struct {
			Requests []DiagnosticRequest `json:"requests"`
		}
		if _, err := api.call(ctx, "GET", "/api/wake/requests?target_id="+t.ID, nil, &history); err != nil {
			return err
		}
		if len(history.Requests) > 50 {
			return fault("invalid_response")
		}
		sort.Slice(history.Requests, func(i, j int) bool { return history.Requests[i].Created > history.Requests[j].Created })
		if len(history.Requests) == 0 {
			fmt.Fprintln(out, "暂无保留中的开机请求。")
		}
		for _, r := range history.Requests {
			fmt.Fprintf(out, "\n  请求：%s\n  状态：%s\n  判断：%s\n", clean(r.ID), clean(r.Phase), explain(r.Phase, r.Error))
			fmt.Fprintf(out, "  提交：%s\n  领取：%s\n  授权：%s\n  发送回执：%s\n  应用上线：%s\n  发送截止：%s\n  观察截止：%s\n", stamp(r.Created), stamp(r.Claimed), stamp(r.Authorized), stamp(r.Sent), stamp(r.Online), stamp(r.Expires), stamp(r.Observe))
			if r.Error != "" {
				fmt.Fprintln(out, "  诊断代码："+clean(r.Error))
			}
		}
	}
	if target != "" && !found {
		return fault("target_not_found")
	}
	if !found {
		fmt.Fprintln(out, "账号下暂无远程开机电脑，请先在 Windows 和手机完成配对。")
	}
	return nil
}
func inspect(dir string) error {
	raw, err := readPrivate(filepath.Join(dir, "config.json"), 8192)
	if err != nil {
		return fault("config_unreadable")
	}
	var c Config
	if json.Unmarshal(raw, &c) != nil {
		return fault("invalid_config")
	}
	fmt.Println("RDesk 家中助手本地诊断（没有发送唤醒包）")
	if err = c.checkNetwork(); err != nil {
		fmt.Println("网络检查：" + explain("failed", "network_changed"))
	} else {
		fmt.Println("网络检查：指定接口、IPv4 和硬件地址符合登记配置。")
	}
	fmt.Println("下方 packet_written 仅代表操作系统接受了 UDP 数据，不证明电脑已收到或已开机。")
	for _, name := range []string{"events.previous.jsonl", "events.jsonl"} {
		raw, err := readPrivate(filepath.Join(dir, name), 300*1024)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return err
		}
		lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
		if len(lines) > 100 {
			lines = lines[len(lines)-100:]
		}
		for _, line := range lines {
			var e Event
			if json.Unmarshal([]byte(line), &e) != nil {
				continue
			}
			fmt.Printf("%s  %s  请求=%s  代码=%s  包数=%d\n", clean(e.Time), clean(e.Event), clean(e.Request), clean(e.Code), e.Packets)
		}
	}
	return nil
}
