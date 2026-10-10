"""Exercise the real installer and selector against isolated temporary configs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SELECTOR = PROJECT / "Scripts/8BitDo_Controller_Selector.sh"
GLOBAL = "input_057e_2009_v3.map"
CORE = "N64_input_057e_2009_v3.map"
EXTRA = "SNES_input_057e_2009_v3.map"
OTHER = "input_2563_0575_v3.map"


class SelectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "fat"
        self.inputs = self.root / "config/inputs"
        self.inputs.mkdir(parents=True)
        self.profiles = self.root / "config/8bitdo-profiles"
        for name, value in [(GLOBAL, b'g'), (CORE, b'c'), (EXTRA, b'e'), (OTHER, b'u')]:
            (self.inputs / name).write_bytes(value * 128)
        self.install()

    def install(self, success=True):
        result = subprocess.run(
            ["bash", str(PROJECT / "install.sh")],
            env=os.environ | {"MISTER_ROOT": str(self.root)},
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

    def run_selector(self, *args, success=True, extra_env=None):
        result = subprocess.run(
            ["bash", str(SELECTOR), *args],
            env=os.environ | {"CONFIG_ROOT": str(self.root / 'config')} | (extra_env or {}),
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.inputs.iterdir()}

    def test_install_preserves_active_maps_and_can_repeat(self):
        self.assertEqual((self.inputs / GLOBAL).read_bytes(), b'g' * 128)
        self.install()
        self.assertEqual((self.inputs / OTHER).read_bytes(), b'u' * 128)

    def test_switch_removes_stale_overrides_and_restore_recovers_them(self):
        before = self.snapshot()
        self.run_selector("apply", "n64")
        self.assertEqual((self.inputs / GLOBAL).read_bytes(), (self.profiles / 'n64' / GLOBAL).read_bytes())
        self.assertFalse((self.inputs / EXTRA).exists())
        self.assertEqual((self.inputs / OTHER).read_bytes(), before[OTHER])
        self.run_selector("restore")
        self.assertEqual(self.snapshot(), before)

    def test_capture_adds_a_core_and_preserves_undo(self):
        self.run_selector("apply", "n64")
        self.run_selector("apply", "stadia")
        pointer = (self.profiles / 'last-backup').read_bytes()
        (self.inputs / EXTRA).write_bytes(b's' * 128)
        self.run_selector("capture", "stadia", "--yes")
        self.assertEqual((self.profiles / 'stadia' / EXTRA).read_bytes(), b's' * 128)
        self.assertEqual((self.profiles / 'last-backup').read_bytes(), pointer)

    def test_invalid_profiles_and_lock_leave_active_maps_unchanged(self):
        before = self.snapshot()
        self.run_selector("apply", "ps4", success=False)
        self.run_selector("apply", "../xbox", success=False)
        (self.profiles / 'n64' / CORE).write_bytes(b'bad')
        self.run_selector("apply", "n64", success=False)
        (self.profiles / '.selector-lock').mkdir()
        self.run_selector("apply", "xbox", success=False)
        self.assertEqual(self.snapshot(), before)

    def test_failed_installation_restores_all_previous_maps(self):
        before = self.snapshot()
        bins = Path(self.temp.name) / 'bin'
        bins.mkdir()
        fake_mv = bins / 'mv'
        fake_mv.write_text('#!/bin/sh\ncase "$*" in *"/inputs/"*) exit 1;; esac\nexec /bin/mv "$@"\n')
        fake_mv.chmod(0o755)
        self.run_selector("apply", "n64", success=False, extra_env={"PATH": str(bins) + ':' + os.environ['PATH']})
        self.assertEqual(self.snapshot(), before)
        self.assertFalse((self.profiles / '.selector-lock').exists())

    def test_installer_refuses_conflicting_profiles(self):
        (self.profiles / 'n64' / GLOBAL).write_bytes(b'd' * 128)
        before = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.install(success=False)
        after = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(after, before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
