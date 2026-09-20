#!/usr/bin/env python3
"""Exercise the deployed HTTP protocol with one temporary account; never logs secrets.

The helper acknowledgement is simulated. This does not test physical Wake-on-LAN.
"""
import argparse
import concurrent.futures
import json
import secrets
import time
import urllib.error
import urllib.request


def check(base):
    password = secrets.token_hex(24)
    username = 'rdesk-smoke-' + secrets.token_hex(8)
    token = None

    def call(path, body=None, auth=None, status=200, method='POST'):
        request = urllib.request.Request(base.rstrip('/') + path,
            data=None if method == 'GET' else json.dumps(body or {}).encode(),
            headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + auth} if auth else {})}, method=method)
        try:
            response = urllib.request.urlopen(request, timeout=15)
        except urllib.error.HTTPError as error:
            response = error
        raw = response.read()
        if response.status != status:
            # Never print request/response bodies, which can contain credentials.
            raise AssertionError(f'{method} {path}: HTTP {response.status}, expected {status}')
        return json.loads(raw) if raw else {}

    try:
        session = call('/api/account/register', {'username': username, 'password': password})
        token = session['token']
        pair = call('/api/wake/pairings', {'name': '协议测试电脑', 'device_id': username, 'mac': '02:11:22:33:44:55'}, token)
        summary = call('/api/wake/pairings/resolve', {'id': pair['id'], 'qr_proof': pair['qr_proof']}, token)
        assert summary['state'] == 'pending' and 'desktop_proof' not in summary
        call('/api/wake/pairings/' + pair['id'] + '/confirm', {'manual_code': pair['manual_code']}, token)
        enrollment_token = secrets.token_hex(32)
        body = {'desktop_proof': pair['desktop_proof'], 'enrollment_token': enrollment_token}
        claimed = call('/api/wake/pairings/' + pair['id'] + '/claim', body, token)
        assert enrollment_token not in json.dumps(claimed)
        assert call('/api/wake/pairings/' + pair['id'] + '/claim', body, token) == claimed
        target = claimed['target_id']
        blocked = call('/api/wake/requests', {'target_id': target}, token, status=409)
        assert blocked['code'] == 'setup_incomplete'
        helper = call('/api/wake/agents', {'name': '模拟家中助手'}, token)
        call('/api/wake/targets/' + target + '/complete', {'agent_id': helper['id'], 'bios_confirmed': True}, token)
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            pending = pool.submit(call, '/api/wake/agents/' + helper['id'] + '/poll', {}, helper['token'])
            time.sleep(.3)
            request = call('/api/wake/requests', {'target_id': target}, token)
            job = pending.result()
        assert job['id'] == request['id']
        rid = request['id']
        call('/api/wake/requests/' + rid + '/authorize-send', {}, helper['token'])
        call('/api/wake/requests/' + rid + '/result', {'phase': 'sent'}, helper['token'])
        state = call('/api/wake/requests/' + rid, auth=token, method='GET')
        assert state['phase'] == 'sent', state['phase']
        time.sleep(.01)
        call('/api/wake/targets/' + target + '/heartbeat', {}, enrollment_token)
        state = call('/api/wake/requests/' + rid, auth=token, method='GET')
        assert state['phase'] == 'online', state['phase']
        old = call('/api/wake/targets', {'name': '旧客户端测试', 'device_id': username + '-old', 'mac': '02:11:22:33:44:66', 'agent_id': helper['id']}, token)
        assert len(old['token']) == 64
        call('/api/wake/targets/' + old['id'] + '/heartbeat', {}, old['token'])
        print('通过：扫码确认、幂等领取、草稿保护、模拟助手认领、发送回执、上线心跳、旧客户端兼容。')
    finally:
        if token:
            call('/api/account/delete', {'password': password}, token)
            print('已删除本次临时测试账号及配置。')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='http://127.0.0.1:28816')
    check(parser.parse_args().base)
