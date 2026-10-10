#!/usr/bin/env python3
"""Check that the account device list reports hosting capability and state.

Uses one temporary account and two simulated devices, removed at the end; never
logs secrets. It exercises the server protocol only: no real computer is
registered, captured or controlled.
"""
import argparse
import json
import secrets
import sys
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='https://qisw.top')
    base = parser.parse_args().base.rstrip('/')
    password = secrets.token_hex(24)
    username = 'rdesk-smoke-' + secrets.token_hex(8)
    token = None
    hosts = []

    def call(path, body=None, auth=None, status=200, method='POST'):
        request = urllib.request.Request(
            base + path,
            data=None if method == 'GET' else json.dumps(body or {}).encode(),
            headers={'Content-Type': 'application/json',
                     **({'Authorization': 'Bearer ' + auth} if auth else {})},
            method=method)
        try:
            response = urllib.request.urlopen(request, timeout=15)
        except urllib.error.HTTPError as error:
            response = error
        raw = response.read()
        if response.status != status:
            # Never print bodies, which can contain credentials.
            raise AssertionError(f'{method} {path}: HTTP {response.status}, expected {status}')
        return json.loads(raw) if raw else {}

    def device_id():
        return '98' + ''.join(secrets.choice('0123456789') for _ in range(7))

    def listed(device):
        devices = call('/api/account/devices', auth=token, method='GET')['devices']
        return next(item for item in devices if item['device_id'] == device)

    def expect(label, device, can_host, hosting):
        item = listed(device)
        got = (item.get('can_host'), item.get('hosting'))
        if got != (can_host, hosting):
            raise AssertionError(f'{label}: can_host/hosting = {got}, expected {(can_host, hosting)}')
        print(f'  通过  {label}')

    def register_host(device):
        host_token = call('/api/preview/register', {
            'device_id': device, 'auth_token': token, 'platform': 'windows',
            'hostname': 'rdesk-smoke', 'password_hash': secrets.token_hex(32),
            'auto_accept': False, 'trusted_viewers': [], 'on_demand_capture': True,
        })['host_token']
        hosts.append((device, host_token))
        return host_token

    try:
        call('/api/account/devices', method='GET', status=401)
        print('  通过  未登录不能读取设备列表')
        token = call('/api/account/register', {'username': username, 'password': password})['token']
        current, outdated = device_id(), device_id()
        call('/api/account/presence', {'device_id': current, 'platform': 'windows',
                                       'hostname': 'smoke-new', 'can_host': True}, token)
        call('/api/account/presence', {'device_id': outdated, 'platform': 'windows',
                                       'hostname': 'smoke-old'}, token)
        expect('上报能力且未开启被控：可被控、未托管', current, True, False)
        expect('不上报能力的旧客户端：不可被控', outdated, False, False)
        register_host(outdated)
        expect('旧客户端登记为主机也不算具备能力', outdated, False, True)
        host_token = register_host(current)
        expect('开启被控后：可被控、托管中', current, True, True)
        call('/api/preview/unregister', {'device_id': current, 'host_token': host_token})
        hosts.remove((current, host_token))
        expect('关闭被控后：可被控、未托管', current, True, False)
    finally:
        for device, host_token in hosts:
            call('/api/preview/unregister', {'device_id': device, 'host_token': host_token})
        if token:
            call('/api/account/delete', {'password': password}, token)
            print('已注销临时测试主机并删除临时测试账号。')
    print('范围：账号设备列表的服务端协议；不代表真实 Windows 电脑已被查看或控制。')


if __name__ == '__main__':
    sys.exit(main())
