#!/usr/bin/env python3
"""Interactive credentials -> pipe only; never save them or accept argv secrets."""
import getpass
import json
import sys

if sys.stdout.isatty():
    sys.exit('请把输出通过管道传给助手 enroll 或 diagnose，避免凭据显示在终端。')
with open('/dev/tty', 'r+', encoding='utf-8') as terminal:
    terminal.write('RDesk 账号：')
    terminal.flush()
    username = terminal.readline().rstrip('\r\n')
password = getpass.getpass('RDesk 密码：')
print(json.dumps({'username': username, 'password': password}))
