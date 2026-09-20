#!/usr/bin/env python3
"""Loopback-only protocol acceptance test; simulated helper/PC, no LAN packets."""
import argparse
import json
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    origin = f'http://127.0.0.1:{port}'

    def call(path, token=None, body=None, method=None, expected=200):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = f'Bearer {token}'
        request = urllib.request.Request(origin + path, headers=headers,
            data=None if body is None else json.dumps(body).encode(), method=method)
        try:
            response = urllib.request.urlopen(request, timeout=8)
        except urllib.error.HTTPError as exc:
            response = exc
        with response:
            data = response.read()
            assert response.status == expected, f'{request.method} {path}: status {response.status}, expected {expected}'
            return json.loads(data) if data else None

    with tempfile.TemporaryDirectory(prefix='rdesk-wake-contract-') as directory:
        with open(Path(directory) / 'server.log', 'wb') as log:
            process = subprocess.Popen([str(binary), '--host', '127.0.0.1',
                '--signaling-port', str(port), '--user-store-path', str(Path(directory) / 'users.json')],
                stdout=log, stderr=subprocess.STDOUT)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError('临时测试服务启动失败')
                    try:
                        call('/health')
                        break
                    except (OSError, urllib.error.URLError):
                        time.sleep(.05)
                else:
                    raise RuntimeError('临时测试服务启动超时')
                owner = call('/api/account/register', body={'username': 'wake-owner', 'password': secrets.token_hex(16)})['token']
                other = call('/api/account/register', body={'username': 'wake-other', 'password': secrets.token_hex(16)})['token']
                call('/api/wake/targets', expected=401)
                helper = call('/api/wake/agents', owner, {'name': '模拟家中助手'})
                pc = call('/api/wake/targets', owner, {'name': '模拟电脑', 'device_id': 'test-windows',
                    'mac': '02:11:22:33:44:55', 'agent_id': helper['id']})
                call('/api/wake/targets', helper['token'], expected=401)
                call(f"/api/wake/agents/{helper['id']}/poll", helper['token'], {}, expected=204)
                request = call('/api/wake/requests', owner, {'target_id': pc['id']})
                assert request['phase'] == 'queued'
                duplicate = call('/api/wake/requests', owner, {'target_id': pc['id']})
                assert duplicate['id'] == request['id']
                base = '/api/wake/requests/' + request['id']
                call(base, other, expected=404)
                claimed = call(f"/api/wake/agents/{helper['id']}/poll", helper['token'], {})
                assert claimed['id'] == request['id'] and claimed['remaining_ms'] > 0
                permit = call(base + '/authorize-send', helper['token'], {})
                assert 0 < permit['remaining_ms'] <= 2000
                call(base + '/result', helper['token'], {'phase': 'sent'})
                assert call(base, owner)['phase'] == 'sent'
                call(f"/api/wake/targets/{pc['id']}/heartbeat", pc['token'], {})
                assert call(base, owner)['phase'] == 'online'
                call(f"/api/wake/agents/{helper['id']}", owner, method='DELETE')
                call(f"/api/wake/agents/{helper['id']}/poll", helper['token'], {}, expected=401)
                stored = (Path(directory) / 'users.json').read_text()
                assert helper['token'] not in stored and pc['token'] not in stored
                print('通过：真实本地 HTTP 全链路、跨账号与角色拒绝、去重、发送/上线分离、撤销、令牌不明文落盘。')
                print('范围：模拟助手与电脑心跳；没有发送局域网数据包，不证明硬件开机。')
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    main()
