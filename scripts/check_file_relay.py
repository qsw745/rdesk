#!/usr/bin/env python3
"""Smoke-test the relay's viewer-to-host file transfer against a deployed server.

Registers one throwaway in-memory preview host (never an account) and plays both
sides: a password viewer uploads a file, the simulated host receives the
`file_receive` command, fetches the bytes once and reports the result. Checks
that the bytes arrive intact, a file can be fetched only once and only by its
host, the name is reduced to a base name, and a refused file is dropped.
The host is unregistered at the end. No real device or account is used and
nothing is written to any computer's disk.
"""
import argparse
import hashlib
import json
import secrets
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request


def call(method, url, body=None, raw=None, timeout=70):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    if body is not None:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
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
    device = '98' + ''.join(secrets.choice('0123456789') for _ in range(7))
    host_token = None

    def q(**kw):
        return urllib.parse.urlencode(kw)

    def next_command():
        for _ in range(4):
            status, payload = call(
                'GET', f'{base}/api/preview/host/control/poll?{q(device_id=device, host_token=host_token)}')
            if status == 200:
                return json.loads(payload)
            expect('主机长轮询', status, 204)
        raise SystemExit('失败：主机没有收到文件命令')

    def answer(command, ok, text=None):
        url = f'{base}/api/preview/host/control/result?{q(device_id=device, host_token=host_token)}'
        return call('POST', url, {'command_id': command['command_id'], 'ok': ok, 'text': text})[0]

    def fetch(file_id, token=None):
        url = f'{base}/api/file/host/download/{file_id}?{q(device_id=device, host_token=token or host_token)}'
        return call('GET', url)

    def send(viewer, filename, data):
        """Uploads in the background, as the viewer waits for the host's answer."""
        result = {}

        def run():
            url = f'{base}/api/file/upload?{q(device_id=device, token=viewer, filename=filename, remote_path="")}'
            result['status'], result['body'] = call('POST', url, raw=data)

        thread = threading.Thread(target=run)
        thread.start()
        return thread, result

    try:
        status, payload = call('POST', f'{base}/api/preview/resolve/{device}', {})
        expect('随机测试设备号未被占用', json.loads(payload).get('found') if status == 200 else status, False)
        status, payload = call('POST', f'{base}/api/preview/register', {
            'device_id': device, 'platform': 'windows', 'hostname': 'rdesk-smoke',
            'password_hash': password_hash, 'auto_accept': False,
            'trusted_viewers': [], 'on_demand_capture': True})
        expect('注册测试主机', status, 200)
        host_token = json.loads(payload)['host_token']

        url = f'{base}/api/file/upload?{q(device_id=device, token="bogus", filename="a.txt", remote_path="")}'
        expect('没有观看会话不能上传', call('POST', url, raw=b'x')[0], 401)

        status, payload = call('POST', f'{base}/api/preview/resolve/{device}', {
            'password_hash': password_hash, 'requester_id': '987000002'})
        resolved = json.loads(payload)
        expect('密码观看者获得授权', resolved.get('authorized'), True)
        viewer = urllib.parse.parse_qs(urllib.parse.urlsplit(resolved['endpoint']).query)['token'][0]

        data = secrets.token_bytes(2 * 1024 * 1024 + 123)
        digest = hashlib.sha256(data).hexdigest()
        thread, result = send(viewer, '../../evil/报告 v2.bin', data)
        command = next_command()
        expect('主机收到文件命令', command['kind'], 'file_receive')
        expect('文件名只保留末段', command['payload']['filename'], '报告 v2.bin')
        expect('文件大小一致', command['payload']['size'], len(data))
        file_id = command['payload']['file_id']
        expect('观看者不能用自己的凭据取回', fetch(file_id, viewer)[0], 401)
        status, received = fetch(file_id)
        expect('主机取回文件', status, 200)
        expect('内容完整（2 MiB 随机数据）', hashlib.sha256(received).hexdigest() == digest, True)
        expect('文件只能取一次', fetch(file_id)[0], 404)
        expect('主机回报已保存', answer(command, True, '报告 v2.bin'), 200)
        thread.join(70)
        expect('观看者得到结果', result.get('status'), 200)
        reply = json.loads(result['body'])
        expect('结果为已保存', reply.get('ok'), True)
        expect('带回保存的文件名', reply.get('saved_as'), '报告 v2.bin')

        thread, result = send(viewer, 'refused.txt', b'no')
        command = next_command()
        refused_id = command['payload']['file_id']
        expect('主机拒收', answer(command, False, None), 200)
        thread.join(70)
        expect('观看者得知未保存', json.loads(result['body']).get('ok'), False)
        expect('被拒收的文件已从中转删除', fetch(refused_id)[0], 404)
    finally:
        if host_token:
            call('POST', f'{base}/api/preview/unregister', {'device_id': device, 'host_token': host_token})
            print('已注销临时测试主机。')
    print('范围：模拟主机与观看者的服务端协议；不代表真实电脑已把文件写入磁盘。')


if __name__ == '__main__':
    sys.exit(main())
