#!/usr/bin/env python3
"""Generate the Windows installer artwork from the app icon geometry.

Writes scripts/installer/:
  wizard-{100,150,200}.png       brand panel on the Welcome / Finished pages (164:314)
  small-{100,150,200}.png        icon tile in the top-right corner of inner pages
  back-{light,dark}-{100,150,200}.png  subtle page backgrounds (497:360)

Sizes follow the Inno Setup 6.7 help for WizardImageFile, WizardSmallImageFile
and WizardBackImageFile at 100/150/200% DPI; Setup picks the closest file.
Uses the same Chrome headless + ImageMagick pipeline as generate_icons.py.
Run from anywhere: python3 design/generate_installer_art.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_icons import CHROME, LARGE, ROOT, Renderer, tile  # noqa: E402

OUT = ROOT / "scripts/installer"
FONT = "'Microsoft YaHei UI','PingFang SC','Segoe UI',sans-serif"

WIZARD = [(202, 386), (336, 643), (430, 824)]
SMALL = [58, 97, 124]
BACK = [(596, 432), (994, 720), (1272, 922)]

# Palette: RdPalette brand blue and the icon's deep-blue gradient.
PANEL = """
<div style="position:absolute;inset:0;background:
  radial-gradient(120% 60% at 100% 0%,rgba(157,194,255,.45),transparent 60%),
  linear-gradient(165deg,#3A7BFF 0%,#2B6BFF 38%,#1531BE 100%)"></div>
<div style="position:absolute;left:0;right:0;top:27%;display:flex;flex-direction:column;align-items:center;font-family:{font};color:#fff">
  <img src="{icon}" style="width:46%;filter:drop-shadow(0 18px 30px rgba(8,20,70,.35))">
  <div style="margin-top:9%;font-size:{title}px;font-weight:700;letter-spacing:.5px">RDesk</div>
  <div style="margin-top:3%;font-size:{sub}px;opacity:.86">连接你的设备</div>
  <div style="margin-top:1.2%;font-size:{sub}px;opacity:.86">随时远程协助</div>
</div>
<div style="position:absolute;left:0;right:0;bottom:4.5%;text-align:center;font-family:{font};font-size:{foot}px;color:#fff;opacity:.55">qisw.top/rdesk</div>
"""

BACKGROUND = """
<div style="position:absolute;inset:0;background:
  radial-gradient(60% 75% at 104% -8%,{glow},transparent 70%),
  radial-gradient(45% 60% at -6% 108%,{warm},transparent 70%),
  {base}"></div>
"""


def render_html(r: Renderer, name: str, body: str, width: int, height: int) -> Path:
    html = r.tmp / f"{name}.html"
    html.write_text('<!doctype html><html><head><meta charset="utf-8"></head>'
                    f'<body style="margin:0;width:{width}px;height:{height}px;position:relative;overflow:hidden">'
                    f"{body}</body></html>")
    out = r.tmp / f"{name}.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--default-background-color=00000000",
                    f"--window-size={width},{height}", f"--screenshot={out}", html.as_uri()],
                   check=True, capture_output=True)
    return out


def resize(src: Path, size: tuple[int, int], dest: Path, alpha: bool) -> None:
    subprocess.run(["magick", str(src), "-filter", "Lanczos", "-resize", f"{size[0]}x{size[1]}!",
                    "-strip", f"PNG32:{dest}" if alpha else f"PNG24:{dest}"], check=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    r = Renderer()
    try:
        icon = r.master("tile", tile(LARGE, 96, 220, True))
        for px in SMALL:
            r.png("tile", tile(LARGE, 96, 220, True), px, OUT / f"small-{SMALL.index(px) * 50 + 100}.png")

        w, h = WIZARD[-1][0] * 2, WIZARD[-1][1] * 2
        panel = render_html(r, "panel", PANEL.format(
            font=FONT, icon=icon.as_uri(), title=round(w * .135), sub=round(w * .062),
            foot=round(w * .045)), w, h)
        for i, size in enumerate(WIZARD):
            resize(panel, size, OUT / f"wizard-{100 + i * 50}.png", alpha=False)

        w, h = BACK[-1]
        themes = {
            "light": dict(base="#FFFFFF", glow="rgba(43,107,255,.10)", warm="rgba(242,106,27,.05)"),
            "dark": dict(base="#15181F", glow="rgba(91,140,255,.20)", warm="rgba(255,138,69,.08)"),
        }
        for theme, colors in themes.items():
            back = render_html(r, f"back-{theme}", BACKGROUND.format(**colors), w, h)
            for i, size in enumerate(BACK):
                resize(back, size, OUT / f"back-{theme}-{100 + i * 50}.png", alpha=False)
    finally:
        r.close()
    print(f"Installer artwork written to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
