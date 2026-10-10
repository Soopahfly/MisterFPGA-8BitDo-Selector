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
            env=os.environ | {"CONFIG_ROOT": str(self.root / 'config'), "RECEIVER_MODE": "switch", "INPUT_DEVICES": "/dev/null"} | (extra_env or {}),
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


    def xinput_env(self):
        return {"RECEIVER_MODE": "xinput"}

    def test_xinput_switch_capture_and_undo_preserve_switch_maps(self):
        before = self.snapshot()
        gx = "input_2dc8_3106_v3.map"
        cx = "N64_input_2dc8_3106_v3.map"
        ex = "SNES_input_2dc8_3106_v3.map"
        advanced = "N64_advanced_input_2dc8_3106_v3.map"
        (self.inputs / gx).write_bytes(b'x' * 128)
        (self.inputs / cx).write_bytes(b'y' * 128)
        (self.inputs / ex).write_bytes(b'z' * 128)
        (self.inputs / advanced).write_bytes(b'a' * 128)
        original = self.snapshot()
        self.run_selector("apply", "xbox", extra_env=self.xinput_env())
        self.assertEqual((self.inputs / gx).read_bytes(), (self.profiles / 'xinput/xbox' / gx).read_bytes())
        self.assertFalse((self.inputs / ex).exists())
        for name, data in before.items():
            self.assertEqual((self.inputs / name).read_bytes(), data)
        self.assertEqual((self.inputs / advanced).read_bytes(), b'a' * 128)
        self.run_selector("restore", extra_env=self.xinput_env())
        self.assertEqual(self.snapshot(), original)
        pointer = (self.profiles / 'xinput/last-backup').read_bytes()
        self.run_selector("capture", "ps4", "--yes", extra_env=self.xinput_env())
        self.assertEqual((self.profiles / 'xinput/ps4' / gx).read_bytes(), b'x' * 128)
        self.assertFalse((self.profiles / 'xinput/ps4' / advanced).exists())
        self.assertEqual((self.profiles / 'xinput/last-backup').read_bytes(), pointer)

    def test_mode_undo_pointers_are_independent(self):
        self.run_selector("apply", "n64")
        before = self.snapshot()
        sw_pointer = (self.profiles / 'last-backup').read_bytes()
        self.run_selector("apply", "xbox", extra_env=self.xinput_env())
        self.assertEqual((self.profiles / 'last-backup').read_bytes(), sw_pointer)
        self.run_selector("restore", extra_env=self.xinput_env())
        self.assertEqual(self.snapshot(), before)  # Empty original XInput maps restored.
        self.assertEqual((self.profiles / 'last-selected').read_text().strip(), 'n64')
        self.assertFalse((self.profiles / 'xinput/last-selected').exists())

    def test_auto_detection_ignores_keyboard_mouse_and_imu(self):
        fixture = Path(self.temp.name) / 'devices'
        fixture.write_text('I: Vendor=2dc8 Product=3106\nN: Name="Receiver Keyboard"\nH: Handlers=kbd event2\n\n'
                           'I: Vendor=057e Product=2009\nN: Name="Pro Controller (IMU)"\nH: Handlers=event3\n\n'
                           'I: Vendor=2dc8 Product=3106\nN: Name="Controller"\nH: Handlers=js0 event4\n')
        env = {"RECEIVER_MODE": "auto", "INPUT_DEVICES": str(fixture)}
        result = self.run_selector("status", extra_env=env)
        self.assertIn('xinput (2dc8:3106)', result.stdout)
        self.run_selector("apply", "stadia", extra_env=env)
        self.assertEqual((self.profiles / 'xinput/last-selected').read_text().strip(), 'stadia')
        self.run_selector("--mode", "switch", "apply", "n64", success=False, extra_env=env)
        fixture.write_text('I: Vendor=057e Product=2009\nN: Name="Pro Controller"\nH: Handlers=event5\n')
        self.assertIn('switch (057e:2009)', self.run_selector("status", extra_env=env).stdout)
        fixture.write_text('')
        before = self.snapshot()
        self.run_selector("apply", "n64", success=False, extra_env=env)
        self.run_selector("--mode", "banana", "apply", "n64", success=False, extra_env=env)
        self.assertEqual(self.snapshot(), before)

    def test_xinput_failure_rolls_back_and_installer_checks_xinput_conflicts(self):
        gx = "input_2dc8_3106_v3.map"
        (self.inputs / gx).write_bytes(b'x' * 128)
        before = self.snapshot()
        bins = Path(self.temp.name) / 'bin'
        bins.mkdir()
        fake_mv = bins / 'mv'
        fake_mv.write_text('#!/bin/sh\ncase "$*" in *"/inputs/"*) exit 1;; esac\nexec /bin/mv "$@"\n')
        fake_mv.chmod(0o755)
        self.run_selector("apply", "xbox", success=False, extra_env=self.xinput_env() | {"PATH": str(bins) + ':' + os.environ['PATH']})
        self.assertEqual(self.snapshot(), before)
        (self.profiles / 'xinput/stadia' / gx).write_bytes(b'd' * 128)
        self.install(success=False)
        self.assertEqual(self.snapshot(), before)

    def test_missing_backup_directory_does_not_erase_active_maps(self):
        (self.profiles / 'last-backup').write_text('backup-missing\n')
        before = self.snapshot()
        self.run_selector("restore", success=False)
        self.assertEqual(self.snapshot(), before)

    def test_offline_menu_can_select_xinput_and_ambiguous_cli_requires_mode(self):
        result = subprocess.run(["bash", str(SELECTOR)], input='1\n3\n\n',
            env=os.environ | {"CONFIG_ROOT": str(self.root / 'config'), "RECEIVER_MODE": "auto", "INPUT_DEVICES": "/dev/null"},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.profiles / 'xinput/last-selected').read_text().strip(), 'xbox')
        fixture = Path(self.temp.name) / 'devices'
        fixture.write_text('I: Vendor=057e Product=2009\nN: Name="Pro Controller"\nH: Handlers=event5\n\n'
                           'I: Vendor=2dc8 Product=3106\nN: Name="Controller"\nH: Handlers=js0 event4\n')
        env = {"RECEIVER_MODE": "auto", "INPUT_DEVICES": str(fixture)}
        before = self.snapshot()
        self.run_selector("apply", "n64", success=False, extra_env=env)
        self.assertEqual(self.snapshot(), before)
        self.run_selector("--mode", "xinput", "apply", "n64", extra_env=env)

if __name__ == "__main__":
    unittest.main(verbosity=2)
