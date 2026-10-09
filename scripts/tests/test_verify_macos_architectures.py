"""Real Mach-O fixtures for the macOS bundle architecture release gate."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
VERIFY = ROOT / "scripts" / "verify_macos_architectures.py"
VERIFY_INSTALL = ROOT / "scripts" / "verify_macos_install.sh"


@unittest.skipUnless(
    sys.platform == "darwin" and shutil.which("clang") and shutil.which("lipo"),
    "需要 macOS 本地 clang 和 lipo",
)
class MacOSArchitectureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = tempfile.TemporaryDirectory(prefix="rdesk-macho-fixtures-")
        cls.fixture_dir = Path(cls.fixtures.name)
        cls.source = cls.fixture_dir / "fixture.c"
        cls.source.write_text("int main(void) { return 0; }\n", encoding="utf-8")
        for arch in ("arm64", "x86_64"):
            for kind in ("executable", "library"):
                command = [
                    "clang", "-arch", arch, "-mmacosx-version-min=11.0",
                    str(cls.source), "-o", str(cls.fixture_dir / f"{arch}-{kind}"),
                ]
                if kind == "library":
                    command.extend(["-dynamiclib", "-Wl,-install_name,@rpath/fixture.dylib"])
                subprocess.run(command, check=True, capture_output=True, text=True)
        for kind in ("executable", "library"):
            subprocess.run(
                [
                    "lipo", "-create", str(cls.fixture_dir / f"arm64-{kind}"),
                    str(cls.fixture_dir / f"x86_64-{kind}"),
                    "-output", str(cls.fixture_dir / f"universal-{kind}"),
                ],
                check=True, capture_output=True, text=True,
            )

    @classmethod
    def tearDownClass(cls):
        cls.fixtures.cleanup()

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="rdesk-bundle-test-")
        self.addCleanup(self.work.cleanup)
        self.app = Path(self.work.name) / "随控 测试.app"
        (self.app / "Contents" / "MacOS").mkdir(parents=True)

    def bundle(self, arch="arm64", executable="renamed-main"):
        with (self.app / "Contents" / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleExecutable": executable, "CFBundleVersion": "1"}, stream)
        self.add_binary(f"Contents/MacOS/{executable}", arch, "executable")

    def add_binary(self, relative, arch="arm64", kind="library"):
        target = self.app / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(self.fixture_dir / f"{arch}-{kind}", target)
        # Libraries need inspection even without an executable bit or filename suffix.
        target.chmod(0o644)
        return target

    def verify(self):
        return subprocess.run(
            [sys.executable, str(VERIFY), str(self.app)],
            capture_output=True, text=True,
        )

    def test_matching_thin_bundle_passes_with_nested_framework_and_helper(self):
        self.bundle()
        library = self.add_binary("Contents/Frameworks/objective_c.framework/Versions/A/objective_c")
        (library.parents[2] / "objective_c").symlink_to("Versions/A/objective_c")
        self.add_binary("Contents/Helpers/rdesk-wake-helper", kind="executable")
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("已检查 3 个 Mach-O", result.stdout)

    def test_intel_framework_in_arm64_bundle_reports_exact_mismatch(self):
        self.bundle()
        relative = "Contents/Frameworks/objective_c.framework/Versions/A/objective_c"
        self.add_binary(relative, "x86_64")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(relative, result.stderr)
        self.assertIn("期望包含 [arm64]", result.stderr)
        self.assertIn("实际 [x86_64]", result.stderr)

    def test_universal_main_rejects_dependency_missing_any_main_architecture(self):
        self.bundle("universal")
        self.add_binary("Contents/Frameworks/partial.dylib", "arm64")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("期望包含 [arm64 x86_64]", result.stderr)
        self.assertIn("缺少 [x86_64]", result.stderr)

    def test_universal_dependencies_cover_universal_main(self):
        self.bundle("universal")
        self.add_binary("Contents/Frameworks/complete.dylib", "universal")
        self.add_binary("Contents/Helpers/universal-helper", "universal", "executable")
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("主程序 [arm64 x86_64]", result.stdout)

    def test_universal_dependency_is_valid_for_thin_main(self):
        self.bundle()
        self.add_binary("Contents/Frameworks/complete.dylib", "universal")
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_incompatible_helper_is_not_ignored(self):
        self.bundle()
        self.add_binary("Contents/Helpers/rdesk-wake-helper", "x86_64", "executable")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Contents/Helpers/rdesk-wake-helper", result.stderr)
        self.assertIn("缺少 [arm64]", result.stderr)

    def test_non_macho_resources_and_scripts_are_ignored(self):
        self.bundle()
        resource = self.app / "Contents" / "Resources"
        resource.mkdir()
        (resource / "data.bin").write_bytes(b"\x00\xff\x00\xff")
        (resource / "launcher").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (resource / "launcher").chmod(0o755)
        # A Java class shares the fat Mach-O magic but is not a native library.
        (resource / "Example.class").write_bytes(b"\xca\xfe\xba\xbe\x00\x00\x00\x34\x00\x01")
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("已检查 1 个 Mach-O", result.stdout)

    def test_missing_plist_executable_fails_with_clear_error(self):
        self.bundle()
        (self.app / "Contents" / "MacOS" / "renamed-main").unlink()
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("主程序不存在", result.stderr)

    def test_install_verifier_runs_architecture_gate_before_signature_check(self):
        self.bundle()
        self.add_binary("Contents/Frameworks/wrong.dylib", "x86_64")
        result = subprocess.run(
            ["bash", str(VERIFY_INSTALL), str(self.app)],
            capture_output=True, text=True, env=os.environ.copy(),
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Contents/Frameworks/wrong.dylib", result.stderr)
        self.assertIn("期望包含 [arm64]", result.stderr)


if __name__ == "__main__":
    unittest.main()
