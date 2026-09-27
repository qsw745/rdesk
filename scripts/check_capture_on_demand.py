#!/usr/bin/env python3
"""Smoke-test the relay's on-demand screen capture protocol against a deployed server.

Registers two throwaway in-memory preview hosts (never an account), then checks:
an on-demand host cannot upload without a viewer, a password viewer's frame
request opens a lease and epoch, the host may then upload, /session/close ends
the lease, and a legacy (not on-demand) host can still upload continuously.
Both hosts are unregistered at the end. No real device, screen or account is used.
"""
import argparse
import hashlib
import json
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request

JPEG = bytes.fromhex('ffd8ffe000104a46494600010100000100010000ffd9')


def call(method, url, body=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    if body is not None:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            payload = r.read()
            return r.status, payload
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def expect(label, got, want):
    ok = got in want if isinstance(want, tuple) else got == want
    print(('通过' if ok else '失败') + f'：{label}（{got}）')
    if not ok:
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='https://qisw.top')
    base = parser.parse_args().base.rstrip('/')
    password_hash = hashlib.sha256(secrets.token_bytes(16)).hexdigest()
    hosts = []

    def q(**kw):
        return urllib.parse.urlencode(kw)

    def register(device_id, on_demand):
        status, payload = call('POST', f'{base}/api/preview/register', {
            'device_id': device_id, 'platform': 'macos', 'hostname': 'rdesk-smoke',
            'password_hash': password_hash, 'auto_accept': False,
            'trusted_viewers': [], 'on_demand_capture': on_demand})
        expect(f'注册{"按需" if on_demand else "旧式"}测试主机', status, 200)
        token = json.loads(payload)['host_token']
        hosts.append((device_id, token))
        return token

    def upload(device_id, token, epoch=None):
        params = dict(device_id=device_id, host_token=token, width=1, height=1)
        if epoch is not None:
            params['capture_epoch'] = epoch
        return call('POST', f'{base}/api/preview/host/frame?{q(**params)}', raw=JPEG)[0]

    def demand(device_id, token):
        status, payload = call('GET', f'{base}/api/preview/host/viewers?{q(device_id=device_id, host_token=token)}')
        expect('查询观看需求', status, 200)
        return json.loads(payload)

    try:
        on_demand = '98' + ''.join(secrets.choice('0123456789') for _ in range(7))
        status, payload = call('POST', f'{base}/api/preview/resolve/{on_demand}', {})
        expect('随机测试设备号未被占用', json.loads(payload).get('found') if status == 200 else status, False)
        host = register(on_demand, True)
        expect('无人观看时拒绝上传', upload(on_demand, host, 0), 409)
        expect('无人观看', demand(on_demand, host)['viewers'], 0)

        status, payload = call('POST', f'{base}/api/preview/resolve/{on_demand}', {
            'password_hash': password_hash, 'requester_id': '987000001'})
        resolved = json.loads(payload)
        expect('密码观看者获得授权', resolved.get('authorized'), True)
        endpoint = resolved['endpoint']
        viewer = urllib.parse.parse_qs(urllib.parse.urlsplit(endpoint).query)['token'][0]
        expect('首次取帧（尚无画面）', call('GET', endpoint)[0], (200, 204, 404, 503))
        current = demand(on_demand, host)
        expect('取帧后产生观看租约', current['viewers'], 1)
        expect('有人观看时允许上传', upload(on_demand, host, current['capture_epoch']), 200)
        status, payload = call('GET', endpoint)
        expect('观看者取到上传的画面', status == 200 and payload[:2] == JPEG[:2], True)
        close = f'{base}/session/close?{q(device_id=on_demand, token=viewer)}'
        expect('公网关闭观看会话', call('POST', close)[0], 200)
        expect('关闭后观看需求清零', demand(on_demand, host)['viewers'], 0)
        expect('关闭后拒绝旧代次上传', upload(on_demand, host, current['capture_epoch']), 409)

        legacy = '98' + ''.join(secrets.choice('0123456789') for _ in range(7))
        legacy_token = register(legacy, False)
        expect('旧式主机无需观看者即可上传', upload(legacy, legacy_token), 200)
    finally:
        for device_id, token in hosts:
            call('POST', f'{base}/api/preview/unregister', {'device_id': device_id, 'host_token': token})
        print(f'已注销 {len(hosts)} 个临时测试主机。')
    print('范围：模拟主机与观看者的服务端协议；不代表真实 Mac 已采集或显示画面。')


if __name__ == '__main__':
    sys.exit(main())
