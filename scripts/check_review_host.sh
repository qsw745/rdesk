#!/usr/bin/env bash
set -uo pipefail

# 审核期间的演示被控端健康检查。
# 覆盖审核员实际会走的完整链路：模拟器在线 → 录屏/无障碍授权 → 服务端可解析
# → 画面确实在推送。任一环节断掉，审核员会看到「未找到在线设备」并以
# Guideline 2.1 打回，因此提交后每天跑一次。
#
# 背景与上架材料见 docs/app-store-submission.md

# 旧默认值 927251902 / Review2026 属于 2026-08-07 作废的模拟器演示环境，
# 留着会让人误以为脚本查的是当前演示机。现改为必须显式传入。
DEVICE_ID="${RDESK_REVIEW_DEVICE_ID:-}"
PASSWORD="${RDESK_REVIEW_PASSWORD:-}"
SERVER="${RDESK_REVIEW_SERVER:-https://qisw.top}"
PACKAGE="com.qsw.rdesk"
ADB_BIN="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"

# 目标设备序列号。多台设备在线时若不指定，adb 会对每条 shell 命令报
# "more than one device/emulator"，脚本随即把在跑的服务误判成「未运行」。
# 这类假警报比漏报更危险：审核期间会让人去「修」根本没坏的东西。
SERIAL="${RDESK_REVIEW_SERIAL:-${ANDROID_SERIAL:-}}"
adb_sh() {
  if [[ -n "$SERIAL" ]]; then
    "$ADB_BIN" -s "$SERIAL" "$@"
  else
    "$ADB_BIN" "$@"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  scripts/check_review_host.sh

检查 App Store 审核用的演示被控端是否可被审核员连接。

环境变量（均有默认值）：
  RDESK_REVIEW_DEVICE_ID   设备 ID（必填）
  RDESK_REVIEW_PASSWORD    连接密码（必填，勿写入文件）
  RDESK_REVIEW_SERVER      服务器地址，默认 https://qisw.top
  RDESK_REVIEW_SERIAL      被控端 adb 序列号；多台设备在线时必填
                           （也认 ANDROID_SERIAL）

退出码：0 = 审核员可正常连接；1 = 存在阻塞问题，需按输出提示修复。
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$DEVICE_ID" || -z "$PASSWORD" ]]; then
  echo "错误：必须提供设备 ID 与密码。" >&2
  echo "  RDESK_REVIEW_DEVICE_ID=<设备ID> RDESK_REVIEW_PASSWORD='<密码>' $0" >&2
  echo "（密码只经环境变量传入，切勿写进文件——本仓库是公开的）" >&2
  exit 1
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
if [[ ! -x "$ADB_BIN" ]]; then
  fail "找不到 adb：$ADB_BIN"
  hint "设置 ANDROID_HOME 指向 Android SDK 目录"
  exit 1
fi

if ! "$ADB_BIN" devices 2>/dev/null | awk 'NR>1 && $2=="device"{found=1} END{exit !found}'; then
  fail "没有在线的 Android 设备"
  hint "启动模拟器：~/Library/Android/sdk/emulator/emulator -avd RDeskDemo -no-audio -no-boot-anim &"
  echo
  echo "结论：审核员当前连不上，必须先恢复演示设备。"
  exit 1
fi
ONLINE_COUNT="$("$ADB_BIN" devices 2>/dev/null | awk 'NR>1 && $2=="device"{n++} END{print n+0}')"
if [[ -z "$SERIAL" && "$ONLINE_COUNT" -gt 1 ]]; then
  fail "有 $ONLINE_COUNT 台设备在线，但未指定序列号"
  hint "指定被控端：RDESK_REVIEW_SERIAL=<序列号> 重跑；序列号见 $ADB_BIN devices -l"
  hint "不指定的话每条 adb shell 都会报 more than one device，"
  hint "在跑的服务会被误判为「未运行/未授权」——本脚本 2026-08-13 曾因此三条假警报"
  echo
  echo "结论：无法判定，请指定序列号后重跑。"
  exit 1
fi
pass "adb 设备在线${SERIAL:+（$SERIAL）}"

# ---- 2. App 与授权状态 ----
if adb_sh shell ps -A 2>/dev/null | grep -q "$PACKAGE"; then
  pass "RDesk 进程运行中"
else
  fail "RDesk 未运行"
  hint "adb${SERIAL:+ -s $SERIAL} shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1"
fi

# types 位掩码 0x20 = FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION，
# 它存在才说明用户确认过系统录屏弹窗、投屏真的在跑。
# types 位掩码 0x20 = FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION。
# 各 ROM 的打印格式不一致：模拟器输出 types=00000020，
# 一加(ColorOS/OxygenOS)输出 types=0x00000020，故 0x 前缀需可选。
if adb_sh shell "dumpsys activity services $PACKAGE" 2>/dev/null \
    | grep -qE "isForeground=true.*types=(0x)?0*20\b"; then
  pass "录屏服务前台运行（已获 MediaProjection 授权）"
else
  fail "录屏未授权或服务未运行"
  hint "模拟器重启会回收录屏权限：进 App「我的 → 移动被控」点「去授权」并确认系统弹窗"
fi

if adb_sh shell settings get secure enabled_accessibility_services 2>/dev/null \
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

# 审核员会在会话页标题看到这个 hostname。2026-08-07 因 Guideline 5.6 被拒的
# 直接原因就是：备注写「Android 手机」，实际上报的是 sdk_gphone64_arm64（模拟器）。
# 这里显式打印出来，便于与审核备注逐字核对。
HOSTNAME_VAL="$(sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p' <<<"$RESOLVE")"
PLATFORM_VAL="$(sed -n 's/.*"platform":"\([^"]*\)".*/\1/p' <<<"$RESOLVE")"
printf "  \033[36mi\033[0m 审核员看到的身份：hostname=%s  platform=%s\n" \
  "${HOSTNAME_VAL:-?}" "${PLATFORM_VAL:-?}"
case "$HOSTNAME_VAL" in
  sdk_gphone*|*emulator*|generic_*)
    fail "这是模拟器标识 —— 不要用它做审核演示机（Guideline 4.2.7 禁止虚拟机）"
    hint "换成真实设备，并确保审核备注里的描述与上面的 hostname 一致"
    ;;
esac

# 注册记录的时效：服务端有 TTL，太旧会被判为陈旧并清理
UPDATED_MS="$(sed -n 's/.*"updated_at_ms":\([0-9]*\).*/\1/p' <<<"$RESOLVE")"
if [[ -n "$UPDATED_MS" ]]; then
  AGE=$(( $(date +%s) - UPDATED_MS / 1000 ))
  # 本机与服务器存在时钟偏差时 AGE 可能为负，钳到 0 避免显示成 "-1s 前"
  (( AGE < 0 )) && AGE=0
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
  # 被控端空闲时不持续推流，有观看者接入才开始推；服务端只保留 30s 内的帧
  # (PREVIEW_TTL_MS)，超时返回 503。因此冷探第一次常是 503，需轮询等它启动，
  # 这也正是审核员点「连接」后的真实过程。
  FRAME="$(mktemp -t rdesk-review-frame.XXXXXX)"
  CODE=""; SIZE=0
  for _ in 1 2 3 4 5 6 7 8; do
    CODE="$(curl -s --max-time 12 -o "$FRAME" -w '%{http_code}' "$ENDPOINT" 2>/dev/null)"
    SIZE="$(wc -c <"$FRAME" | tr -d ' ')"
    [[ "$CODE" == "200" && "$SIZE" -gt 1000 ]] && break
    perl -e 'select(undef,undef,undef,2)' 2>/dev/null || true
  done
  if [[ "$CODE" == "200" && "$SIZE" -gt 1000 ]]; then
    DIMS="$(sips -g pixelWidth -g pixelHeight "$FRAME" 2>/dev/null \
      | awk -F': ' '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{if(w) printf "%sx%s", w, h}')"
    pass "画面可拉取 ${DIMS:+($DIMS, }${SIZE} 字节${DIMS:+)}"

    # 仅凭「拉到一帧」不能判定画面是活的：投屏被系统回收后，被控端会把最后
    # 一张缓存帧反复重传，服务端看到的帧始终「新鲜」、状态码始终 200，
    # 而观看端看到的是一张定格的死图。
    #
    # 内容哈希不变并不能直接判死——静止的屏幕本来就不产生新画面。
    # 因此以 dumpsys media_projection 是否存在活动会话作为权威判据，
    # 哈希变化仅作为「确实在更新」的正向佐证。
    # 输出形如：
    #   MEDIA PROJECTION MANAGER (dumpsys media_projection)
    #   Media Projection:
    #   null                       ← 会话为空时值单独占一行
    # 去掉首行标题并压掉空白后得到 "MediaProjection:<值>"，取冒号后的值判断。
    PROJECTION="$(adb_sh shell dumpsys media_projection 2>/dev/null \
      | tr -d '\r' | sed -n '2,$p' | tr -d '[:space:]')"
    PROJECTION_VALUE="${PROJECTION#*MediaProjection:}"
    if [[ -z "$PROJECTION_VALUE" || "$PROJECTION_VALUE" == "null" ]]; then
      fail "投屏会话已被系统回收 —— 画面已冻结，审核员只会看到定格的旧图"
      hint "进 App「我的 → 移动被控」关闭共享再重新开启，并重新确认录屏弹窗"
      hint "服务端此时仍返回 200，只看状态码会被误导"
    else
      pass "投屏会话存活（dumpsys media_projection 有活动会话）"
      HASH1="$(shasum -a 256 "$FRAME" | cut -d' ' -f1)"
      CHANGED=0
      for _ in 1 2 3; do
        perl -e 'select(undef,undef,undef,2)' 2>/dev/null || true
        curl -s --max-time 12 -o "$FRAME" "$ENDPOINT" 2>/dev/null || true
        HASH2="$(shasum -a 256 "$FRAME" 2>/dev/null | cut -d' ' -f1)"
        if [[ -n "$HASH2" && "$HASH2" != "$HASH1" ]]; then
          CHANGED=1
          break
        fi
      done
      if (( CHANGED == 1 )); then
        pass "画面内容在更新"
      else
        warn "6 秒内画面内容无变化 —— 屏幕静止时属正常，投屏会话已确认存活"
      fi
    fi
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
