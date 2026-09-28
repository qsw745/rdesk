#!/usr/bin/env python3
"""Generate every RDesk app icon from one geometry definition.

Mark: a light "remote" screen behind a deep-blue "local" screen, with an orange
pointer reaching from the local screen into the remote one. White background.

Writes design/app-icon.svg (the master) and all platform assets:
iOS, macOS, Android (adaptive, legacy, themed monochrome, notification),
Windows .ico and the website icon.

Requires Google Chrome (headless SVG rendering) and ImageMagick (`magick`).
Run from anywhere: python3 design/generate_icons.py
"""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "flutter_client"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

POINTER = "M0 0 L0 74 L17.5 58 L29 85 L43 79 L31.5 52.5 L54 52.5 Z"
DEFS = """
 <linearGradient id="deep" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3A7BFF"/><stop offset="1" stop-color="#1531BE"/></linearGradient>
 <linearGradient id="light" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9DC2FF"/><stop offset="1" stop-color="#5F90FF"/></linearGradient>
 <linearGradient id="warm" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFA84E"/><stop offset="1" stop-color="#FF6423"/></linearGradient>
 <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="12" stdDeviation="12" flood-color="#0B1A3A" flood-opacity="0.22"/></filter>
"""

# (scale, gap, pointer outline). Small sizes get a larger mark and thicker gaps.
LARGE = (1.1, 30, 11)
SMALL = (1.32, 44, 17)


def mark(scale: float, gap: int, outline: int, around: float = 512) -> str:
    """Colour mark centred on (around, around) of a 1024 canvas."""
    return f"""<g transform="translate({around} {around}) scale({scale}) translate(-512 -512)">
 <rect x="212" y="262" width="440" height="320" rx="62" fill="url(#light)"/>
 <rect x="372" y="442" width="440" height="320" rx="62" fill="url(#deep)" stroke="#fff" stroke-width="{gap}"/>
 <path d="{POINTER}" transform="translate(424 344) scale(3.25)" fill="url(#warm)" stroke="#fff" stroke-width="{outline}" stroke-linejoin="round" paint-order="stroke"/>
</g>"""


def silhouette(scale: float, gap: int, outline: int) -> str:
    """Single-colour mark: the pointer sits in a cut-out, and the front screen is cut out of the back one."""
    t = f"translate(512 512) scale({scale}) translate(-512 -512)"
    pointer = f'<path d="{POINTER}" transform="translate(424 344) scale(3.25)" stroke-linejoin="round"'
    front = '<rect x="372" y="442" width="440" height="320" rx="62"'
    return f"""<defs>
 <mask id="back" maskUnits="userSpaceOnUse"><rect width="1024" height="1024" fill="#fff"/>
  {front} fill="#000" stroke="#000" stroke-width="{gap}"/>{pointer} fill="#000" stroke="#000" stroke-width="{outline * 2}"/></mask>
 <mask id="front" maskUnits="userSpaceOnUse"><rect width="1024" height="1024" fill="#fff"/>
  {pointer} fill="#000" stroke="#000" stroke-width="{outline * 2}"/></mask>
</defs>
<g transform="{t}" fill="#fff">
 <rect x="212" y="262" width="440" height="320" rx="62" mask="url(#back)"/>
 {front} mask="url(#front)"/>
 {pointer}/>
</g>"""


def svg(body: str, defs: str = DEFS) -> str:
    return (f'<svg width="1024" height="1024" viewBox="0 0 1024 1024" '
            f'xmlns="http://www.w3.org/2000/svg"><defs>{defs}</defs>{body}</svg>')


def full(size: tuple) -> str:
    """Opaque full-bleed square; the platform applies its own mask (iOS)."""
    return svg('<rect width="1024" height="1024" fill="#fff"/>' + mark(*size))


def tile(size: tuple, inset: int, radius: int, shadow: bool) -> str:
    """White rounded tile on a transparent canvas (macOS, Windows, web, legacy Android)."""
    span = 1024 - 2 * inset
    style = ' filter="url(#shadow)"' if shadow else ""
    scale = size[0] * span / 1024
    return svg(
        f'<rect x="{inset}" y="{inset}" width="{span}" height="{span}" rx="{radius}" fill="#fff"{style}/>'
        f'<rect x="{inset + 1}" y="{inset + 1}" width="{span - 2}" height="{span - 2}" rx="{radius - 1}" '
        f'fill="none" stroke="#0B1A3A" stroke-opacity="0.08" stroke-width="2"/>'
        + mark(scale, size[1], size[2]))


def adaptive_foreground() -> str:
    # Android masks to at most a 66dp circle of the 108dp canvas; keep the mark inside it.
    return svg(mark(0.8, 30, 11))


def mono(scale: float) -> str:
    return svg(silhouette(scale, 36, 14), defs="")


class Renderer:
    def __init__(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="rdesk-icons-"))
        self.cache: dict[str, Path] = {}

    def master(self, name: str, source: str) -> Path:
        if name not in self.cache:
            html = self.tmp / f"{name}.html"
            html.write_text('<!doctype html><html><body style="margin:0;background:transparent">'
                            f"{source}</body></html>")
            out = self.tmp / f"{name}.png"
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                            "--default-background-color=00000000", "--window-size=1024,1024",
                            f"--screenshot={out}", html.as_uri()],
                           check=True, capture_output=True)
            self.cache[name] = out
        return self.cache[name]

    def png(self, name: str, source: str, px: int, dest: Path, opaque: bool = False) -> None:
        dest.parent.mkdir(parents=True, exist_ok=True)
        # -strip drops timestamps so reruns are byte-for-byte reproducible.
        args = ["magick", str(self.master(name, source)), "-filter", "Lanczos",
                "-resize", f"{px}x{px}", "-strip"]
        if opaque:
            args += ["-background", "#fff", "-alpha", "remove", "-alpha", "off"]
        subprocess.run(args + [f"PNG32:{dest}" if not opaque else f"PNG24:{dest}"], check=True)

    def close(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)


def pick(px: int) -> tuple:
    return SMALL if px <= 40 else LARGE


def main() -> None:
    r = Renderer()
    try:
        (ROOT / "design/app-icon.svg").write_text(
            full(LARGE).replace("<defs>", "<title>RDesk 应用图标</title><desc>白底；浅蓝远端屏幕在后，深蓝本地屏幕在前，"
                                "橙色光标从本地伸入远端，表示远程操控。</desc><defs>", 1) + "\n")
        r.png("full", full(LARGE), 1024, ROOT / "design/app-icon-1024.png", opaque=True)

        ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        for item in json.loads((ios / "Contents.json").read_text())["images"]:
            px = round(float(item["size"].split("x")[0]) * int(item["scale"].rstrip("x")))
            name, size = ("full-small", SMALL) if px <= 40 else ("full", LARGE)
            r.png(name, full(size), px, ios / item["filename"], opaque=True)

        # macOS icon grid: 824pt rounded tile with shadow inside the 1024 canvas.
        mac = APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
        for px in (16, 32, 64, 128, 256, 512, 1024):
            size = pick(px)
            r.png(f"mac-{size[0]}", tile(size, 100, 185, True), px, mac / f"app_icon_{px}.png")

        res = APP / "android/app/src/main/res"
        for density, dp in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
            launcher, layer, stat = round(48 * dp), round(108 * dp), round(24 * dp)
            r.png("android-legacy", tile(LARGE, 40, 190, False), launcher,
                  res / f"mipmap-{density}/ic_launcher.png")
            r.png("android-fg", adaptive_foreground(), layer, res / f"mipmap-{density}/ic_launcher_foreground.png")
            r.png("android-mono", mono(0.8), layer, res / f"mipmap-{density}/ic_launcher_monochrome.png")
            r.png("notification", mono(1.5), stat, res / f"drawable-{density}/ic_stat_rdesk.png")
        (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
        (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n')
        (res / "values/ic_launcher_background.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            '    <color name="ic_launcher_background">#FFFFFF</color>\n</resources>\n')

        ico_parts = []
        for px in (16, 24, 32, 48, 64, 128, 256):
            part = r.tmp / f"ico-{px}.png"
            size = pick(px)
            r.png(f"win-{size[0]}", tile(size, 24, 190, False), px, part)
            ico_parts.append(str(part))
        subprocess.run(["magick", *ico_parts, str(APP / "windows/runner/resources/app_icon.ico")], check=True)

        r.png("web", tile(LARGE, 24, 190, False), 512, ROOT / "deploy/icon.png")
        # In-app brand mark (sidebar, about page): transparent, mark only.
        r.png("brand-mark", svg(mark(1.55, 30, 11)), 256, APP / "assets/brand/mark.png")
        r.png("brand-tile", tile(LARGE, 24, 190, False), 256, APP / "assets/brand/app_icon.png")
    finally:
        r.close()
    print("图标已生成：design、iOS、macOS、Android、Windows、官网。")


if __name__ == "__main__":
    main()
