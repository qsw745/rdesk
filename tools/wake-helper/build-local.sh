#!/bin/sh
set -eu
cd "$(dirname "$0")"
out=${1:?请传入本地输出目录的绝对路径}
case "$out" in /*) ;; *) echo '输出目录必须是绝对路径' >&2; exit 1;; esac
mkdir -p "$out"
go test ./...
go vet ./...
for target in linux/amd64 linux/arm64 linux/arm darwin/arm64 darwin/amd64; do
  platform=${target%/*}
  arch=${target#*/}
  name=rdesk-wake-helper-0.1.0-$platform-$arch
  if [ "$arch" = arm ]; then name=${name}v7; fi
  CGO_ENABLED=0 GOOS="$platform" GOARCH="$arch" GOARM=7 \
    go build -trimpath -ldflags='-s -w -buildid=' -o "$out/$name" .
done
(cd "$out" && shasum -a 256 rdesk-wake-helper-0.1.0-* > SHA256SUMS)
echo '本地编译完成。通用 Linux 成品不代表已适配任意原厂路由器固件。'
