#!/usr/bin/env python3
"""App Store Connect API 小工具。

用途：不开浏览器、不依赖 ASC 网页登录态，直接查询构建状态、补出口合规、
查看 TestFlight 群组分发情况。网页登录态过期时尤其有用。

不依赖第三方库：ES256 的 JWT 用 openssl 签名后手工转成 r||s 定长格式。

凭据（三项都不写进仓库）：
  ASC_KEY_ID      密钥 ID，即 AuthKey_XXXXXXXXXX.p8 文件名中的那段
  ASC_ISSUER_ID   Issuer ID，见 ASC → 用户和访问 → 集成 → App Store Connect API
  ASC_KEY_PATH    .p8 私钥路径，默认 ~/private_keys/AuthKey_<KEY_ID>.p8

建议写进 ~/.zshrc（私钥本身放 ~/private_keys/，权限 600，切勿入库）：
  export ASC_KEY_ID=...
  export ASC_ISSUER_ID=...

用法：
  scripts/asc.py builds                 列出最近构建及其处理状态与出口合规
  scripts/asc.py groups                 列出 TestFlight 群组及各自包含的构建
  scripts/asc.py compliance <版本号>     把该构建的出口合规标记为「豁免」

关于 compliance 子命令：它把 usesNonExemptEncryption 设为 false，
含义是「本 App 只使用可豁免的加密」。**这是法律申报**，仅在你已经确认
App 确实符合豁免条件时才可使用。RDesk 的判断依据见
docs/app-store-submission.md 第四节。

未回答出口合规的构建，ASC 不会分发给 TestFlight 测试员，也无法提交审核——
症状是「构建已处理完成，但 TestFlight 里看不到」。
"""

import base64
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

APP_ID = os.environ.get("ASC_APP_ID", "6796165712")
API = "https://api.appstoreconnect.apple.com/v1"


def fail(message):
    print(f"错误：{message}", file=sys.stderr)
    raise SystemExit(1)


def b64u(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_to_raw(der):
    """openssl 输出 DER SEQUENCE，ES256 要求 r||s 各 32 字节定长。"""
    if der[0] != 0x30:
        fail("签名格式异常，不是 DER SEQUENCE")
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        if der[i] != 0x02:
            fail("签名格式异常，缺少 INTEGER")
        length = der[i + 1]
        value = der[i + 2 : i + 2 + length].lstrip(b"\x00")
        out += value.rjust(32, b"\x00")
        i += 2 + length
    return out


def token():
    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer:
        fail(
            "请先设置 ASC_KEY_ID 与 ASC_ISSUER_ID\n"
            "  Key ID    取自 AuthKey_XXXXXXXXXX.p8 的文件名\n"
            "  Issuer ID 见 ASC → 用户和访问 → 集成 → App Store Connect API"
        )
    key_path = pathlib.Path(
        os.environ.get("ASC_KEY_PATH")
        or (pathlib.Path.home() / "private_keys" / f"AuthKey_{key_id}.p8")
    ).expanduser()
    if not key_path.is_file():
        fail(f"找不到私钥：{key_path}")

    now = int(time.time())
    header = b64u(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"},
                             separators=(",", ":")).encode())
    payload = b64u(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200,
                               "aud": "appstoreconnect-v1"},
                              separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}"
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=signing_input.encode(), capture_output=True,
    )
    if result.returncode != 0:
        fail(f"openssl 签名失败：{result.stderr.decode().strip()}")
    return f"{signing_input}.{b64u(der_to_raw(result.stdout))}"


def request(path, method="GET", body=None):
    req = urllib.request.Request(
        f"{API}{path}", method=method,
        data=json.dumps(body).encode() if body else None,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        try:
            errors = json.loads(detail).get("errors", [])
            detail = errors[0].get("detail", detail) if errors else detail
        except json.JSONDecodeError:
            pass
        fail(f"HTTP {error.code}：{detail}")


def cmd_builds():
    data = request(f"/builds?filter%5Bapp%5D={APP_ID}&limit=10").get("data", [])
    if not data:
        print("没有构建")
        return
    print(f"{'构建':>4}  {'处理状态':<10}  {'出口合规':<8}  已过期")
    for item in data:
        a = item["attributes"]
        compliance = a.get("usesNonExemptEncryption")
        label = {None: "未回答", True: "非豁免", False: "豁免"}.get(compliance, str(compliance))
        flag = "  ← 未回答将无法分发/提交" if compliance is None else ""
        print(f"{a.get('version'):>4}  {a.get('processingState'):<10}  {label:<8}  "
              f"{a.get('expired')}{flag}")


def cmd_groups():
    groups = request(f"/betaGroups?filter%5Bapp%5D={APP_ID}").get("data", [])
    if not groups:
        print("没有 TestFlight 群组")
        return
    for group in groups:
        a = group["attributes"]
        kind = "内部" if a.get("isInternalGroup") else "外部"
        builds = request(f"/betaGroups/{group['id']}/builds").get("data", [])
        versions = ", ".join(b["attributes"].get("version") for b in builds) or "空"
        print(f"[{kind}] {a.get('name')}：{versions}")


def cmd_compliance(version):
    data = request(f"/builds?filter%5Bapp%5D={APP_ID}&limit=20").get("data", [])
    target = next((b for b in data if b["attributes"].get("version") == version), None)
    if not target:
        fail(f"找不到构建 {version}")
    current = target["attributes"].get("usesNonExemptEncryption")
    if current is False:
        print(f"构建 {version} 的出口合规已是「豁免」，无需改动")
        return
    request(
        f"/builds/{target['id']}", method="PATCH",
        body={"data": {"type": "builds", "id": target["id"],
                       "attributes": {"usesNonExemptEncryption": False}}},
    )
    print(f"构建 {version} 出口合规已标记为「豁免」；TestFlight 分发通常几分钟内生效")


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return
    command = args[0]
    if command == "builds":
        cmd_builds()
    elif command == "groups":
        cmd_groups()
    elif command == "compliance":
        if len(args) < 2:
            fail("用法：scripts/asc.py compliance <版本号>")
        cmd_compliance(args[1])
    else:
        fail(f"未知命令：{command}（可用：builds / groups / compliance）")


if __name__ == "__main__":
    main()
