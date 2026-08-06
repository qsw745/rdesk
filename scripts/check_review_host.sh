#!/usr/bin/env bash
set -uo pipefail

# 审核期间的演示被控端健康检查。
# 覆盖审核员实际会走的完整链路：模拟器在线 → 录屏/无障碍授权 → 服务端可解析
# → 画面确实在推送。任一环节断掉，审核员会看到「未找到在线设备」并以
# Guideline 2.1 打回，因此提交后每天跑一次。
#
# 背景与上架材料见 docs/app-store-submission.md

DEVICE_ID="${RDESK_REVIEW_DEVICE_ID:-927251902}"
PASSWORD="${RDESK_REVIEW_PASSWORD:-Review2026}"
SERVER="${RDESK_REVIEW_SERVER:-https://qisw.top}"
PACKAGE="com.qsw.rdesk"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"

usage() {
  cat <<'EOF'
Usage:
  scripts/check_review_host.sh

检查 App Store 审核用的演示被控端是否可被审核员连接。

环境变量（均有默认值）：
  RDESK_REVIEW_DEVICE_ID   设备 ID，默认 927251902
  RDESK_REVIEW_PASSWORD    连接密码，默认 Review2026
  RDESK_REVIEW_SERVER      服务器地址，默认 https://qisw.top

退出码：0 = 审核员可正常连接；1 = 存在阻塞问题，需按输出提示修复。
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

FAILED=0

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAILED=1; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }
hint() { printf "      → %s\n" "$1"; }

echo "演示被控端检查  device=$DEVICE_ID  server=$SERVER"
echo

# ---- 1. 模拟器 / 实体设备是否连上 adb ----
echo "[1/4] Android 被控端"
if [[ ! -x "$ADB" ]]; then
  fail "找不到 adb：$ADB"
  hint "设置 ANDROID_HOME 指向 Android SDK 目录"
  exit 1
fi

if ! "$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device"{found=1} END{exit !found}'; then
  fail "没有在线的 Android 设备"
  hint "启动模拟器：~/Library/Android/sdk/emulator/emulator -avd RDeskDemo -no-audio -no-boot-anim &"
  echo
  echo "结论：审核员当前连不上，必须先恢复演示设备。"
  exit 1
fi
pass "adb 设备在线"

# ---- 2. App 与授权状态 ----
if "$ADB" shell ps -A 2>/dev/null | grep -q "$PACKAGE"; then
  pass "RDesk 进程运行中"
else
  fail "RDesk 未运行"
  hint "$ADB shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1"
fi

# types 位掩码 0x20 = FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION，
# 它存在才说明用户确认过系统录屏弹窗、投屏真的在跑。
if "$ADB" shell "dumpsys activity services $PACKAGE" 2>/dev/null \
    | grep -q "isForeground=true.*types=00000020"; then
  pass "录屏服务前台运行（已获 MediaProjection 授权）"
else
  fail "录屏未授权或服务未运行"
  hint "模拟器重启会回收录屏权限：进 App「我的 → 移动被控」点「去授权」并确认系统弹窗"
fi

if "$ADB" shell settings get secure enabled_accessibility_services 2>/dev/null \
    | grep -q "$PACKAGE"; then
  pass "无障碍服务已启用（远程操控可下发）"
else
  fail "无障碍服务未启用，审核员只能看画面、无法操作"
  hint "设置 → 无障碍 → 已下载的应用 → RDesk → 开启"
fi

# ---- 3. 服务端能否解析并鉴权 ----
echo
echo "[2/4] 服务端解析"
HASH="$(printf '%s' "$PASSWORD" | shasum -a 256 | awk '{print $1}')"
RESOLVE="$(curl -s --max-time 15 -X POST "$SERVER/api/preview/resolve/$DEVICE_ID" \
  -H 'Content-Type: application/json' \
  -d "{\"password_hash\":\"$HASH\",\"requester_id\":\"review-precheck\"}" 2>/dev/null)"

if [[ -z "$RESOLVE" ]]; then
  fail "服务器无响应：$SERVER"
  hint "检查服务器 101.37.21.147 与 nginx 是否正常"
  echo
  exit 1
fi

if ! grep -q '"found":true' <<<"$RESOLVE"; then
  fail "服务端查不到该设备（审核员会看到「未找到在线设备」）"
  hint "被控端未注册或注册已过期，重启 App 让它重新上报"
  echo "      响应：$RESOLVE"
  echo
  echo "结论：审核员当前连不上，必须先恢复演示设备。"
  exit 1
fi
pass "设备已注册且在线"

AUTHORIZED=0
if grep -q '"authorized":true' <<<"$RESOLVE"; then
  AUTHORIZED=1
  pass "密码校验通过（与审核备注中的密码一致）"
else
  fail "密码不匹配 —— 审核备注里的密码连不上"
  hint "被控端密码已被改动：把它改回审核备注里的密码，或同步更新 ASC 审核备注"
fi

# 注册记录的时效：服务端有 TTL，太旧会被判为陈旧并清理
UPDATED_MS="$(sed -n 's/.*"updated_at_ms":\([0-9]*\).*/\1/p' <<<"$RESOLVE")"
if [[ -n "$UPDATED_MS" ]]; then
  AGE=$(( $(date +%s) - UPDATED_MS / 1000 ))
  if (( AGE < 120 )); then
    pass "心跳新鲜（${AGE}s 前）"
  else
    warn "心跳已 ${AGE}s 未更新，被控端可能正在掉线"
  fi
fi

# ---- 4. 画面是否真的在推 ----
echo
echo "[3/4] 实时画面"
ENDPOINT="$(sed -n 's/.*"endpoint":"\([^"]*\)".*/\1/p' <<<"$RESOLVE")"
if (( AUTHORIZED == 0 )); then
  # 鉴权没过时服务端本就不返回画面地址，这里不重复计一次失败
  warn "跳过 —— 鉴权未通过，服务端不会下发画面地址（先修上一步）"
elif [[ -z "$ENDPOINT" ]]; then
  fail "响应中没有画面地址"
else
  FRAME="$(mktemp -t rdesk-review-frame.XXXXXX)"
  CODE="$(curl -s --max-time 15 -o "$FRAME" -w '%{http_code}' "$ENDPOINT" 2>/dev/null)"
  SIZE="$(wc -c <"$FRAME" | tr -d ' ')"
  if [[ "$CODE" == "200" && "$SIZE" -gt 1000 ]]; then
    DIMS="$(sips -g pixelWidth -g pixelHeight "$FRAME" 2>/dev/null \
      | awk -F': ' '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{if(w) printf "%sx%s", w, h}')"
    pass "画面正常推送 ${DIMS:+($DIMS, }${SIZE} 字节${DIMS:+)}"
  else
    fail "拉取画面失败 http=$CODE size=$SIZE"
    hint "录屏授权可能已被回收，重新进「我的 → 移动被控」授权"
  fi
  rm -f "$FRAME"
fi

# ---- 5. 审核依赖的对外页面 ----
echo
echo "[4/4] 审核所需页面"
for path in /rdesk/privacy /rdesk/support; do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$SERVER$path" 2>/dev/null)"
  if [[ "$CODE" == "200" ]]; then
    pass "$SERVER$path"
  else
    fail "$SERVER$path 返回 $CODE（ASC 中填写的链接必须可访问）"
  fi
done

echo
if (( FAILED == 0 )); then
  echo -e "\033[32m结论：审核员可以正常连接演示设备。\033[0m"
else
  echo -e "\033[31m结论：存在阻塞问题，按上面的 → 提示修复后重跑。\033[0m"
fi
exit "$FAILED"
