#!/usr/bin/env python3
"""Generate the complete static site locally. CI only uploads this directory."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(root / "scripts/render_download_page.py")], check=True)
site = root / "deploy/site"
site.mkdir(exist_ok=True)
for name in ("index.html", "icon.png", "releases.json"):
    shutil.copy2(root / "deploy" / name, site / name)
for name in ("download", "support", "privacy"):
    (site / name).mkdir(exist_ok=True)
    shutil.copy2(root / "deploy" / (name + ".html"), site / name / "index.html")
(site / ".nojekyll").write_text("")
print("本地静态官网已准备：deploy/site；发布流程只上传成品。")
