#!/usr/bin/env python3
"""Reject macOS bundles with native files missing a main executable architecture."""

import argparse
from pathlib import Path
import plistlib
import subprocess
import sys


MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


def tool_output(command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"检查文件失败：{command[-1]}；{result.stderr.strip()}")
    return result.stdout.strip()


def is_macho(path):
    with path.open("rb") as stream:
        if stream.read(4) not in MACHO_MAGICS:
            return False
    # Java class files share the fat Mach-O magic; inspect before calling lipo.
    return "Mach-O" in tool_output(["/usr/bin/file", "-b", "--", str(path)])


def architectures(path):
    result = set(tool_output(["/usr/bin/lipo", "-archs", str(path)]).split())
    if not result:
        raise ValueError(f"无法读取 Mach-O 架构：{path}")
    return result


def format_architectures(values):
    return " ".join(sorted(values))


def verify_bundle(app):
    plist_path = app / "Contents" / "Info.plist"
    with plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or Path(executable).name != executable:
        raise ValueError(f"Info.plist 缺少有效的 CFBundleExecutable：{plist_path}")
    main = app / "Contents" / "MacOS" / executable
    if not main.is_file():
        raise ValueError(f"主程序不存在：{main}")
    if not is_macho(main):
        raise ValueError(f"主程序不是 Mach-O 文件：{main}")
    expected = architectures(main)
    checked = set()
    failures = []
    # Search the entire bundle, including versioned frameworks, nested bundles,
    # helpers and native libraries without filename suffixes or executable bits.
    for path in sorted(app.rglob("*")):
        if not path.is_file():
            continue
        resolved = path.resolve()
        if resolved in checked or not is_macho(path):
            continue
        checked.add(resolved)
        actual = architectures(path)
        missing = expected - actual
        if missing:
            failures.append(
                f"{path.relative_to(app)}；期望包含 [{format_architectures(expected)}]，"
                f"实际 [{format_architectures(actual)}]，缺少 [{format_architectures(missing)}]"
            )
    if failures:
        raise ValueError("架构不兼容：\n" + "\n".join(failures))
    return expected, len(checked)


def main():
    parser = argparse.ArgumentParser(description="验证 macOS 应用包内全部 Mach-O 文件的架构兼容性")
    parser.add_argument("app", type=Path, help="待验证的 .app 路径")
    args = parser.parse_args()
    app = args.app.resolve()
    try:
        expected, count = verify_bundle(app)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"macOS 架构验证失败：{error}", file=sys.stderr)
        return 1
    print(
        f"macOS 架构验证通过：主程序 [{format_architectures(expected)}]，"
        f"已检查 {count} 个 Mach-O 文件：{app}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
