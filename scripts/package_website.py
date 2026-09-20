#!/usr/bin/env python3
"""Validate prebuilt installers and package the website locally for upload."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--artifacts', type=Path, action='append', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
site = root / 'deploy/site'
metadata = json.loads((site / 'releases.json').read_text())
files = {str(Path('rdesk') / f.relative_to(site)): f.read_bytes()
         for f in site.rglob('*') if f.is_file()}
checksums = []
for name, expected in metadata['files'].items():
    if Path(name).name != name:
        raise SystemExit(f'无效文件名：{name}')
    candidate = next((d / name for d in args.artifacts if (d / name).is_file()), None)
    if candidate is None:
        raise SystemExit(f'缺少本地安装包：{name}')
    data = candidate.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != expected['bytes'] or digest != expected['sha256']:
        raise SystemExit(f'安装包校验失败：{name}')
    files[f'rdesk/dl/{name}'] = data
    checksums.append(f'{digest}  {name}\n')
files['rdesk/dl/SHA256SUMS.txt'] = ''.join(checksums).encode()
manifest = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n'
                   for name, data in sorted(files.items()))
files['MANIFEST.sha256'] = manifest.encode()
args.output.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(args.output, 'w:gz') as archive:
    for name, data in sorted(files.items()):
        info = tarfile.TarInfo(name)
        info.size, info.mode = len(data), 0o644
        info.uid = info.gid = 0
        info.uname = info.gname = 'root'
        archive.addfile(info, io.BytesIO(data))
print(f'官网和 {len(checksums)} 个已验证安装包已在本地打包：{args.output}')
