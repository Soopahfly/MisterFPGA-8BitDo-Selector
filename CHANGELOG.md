# Changelog

## 0.3.2 - 2026-10-11

- Moved the complete updater into the main selector. Added Update selector to controller and numbered keyboard menus, the offline mode screen, and the `update [--no-pause]` command.
- Fresh installs no longer create a separate updater entry. Built-in updates back up and remove an existing legacy updater, while a repository compatibility bridge lets v0.3.1 users upgrade.
- Profile preservation, verified downloads, shared locking, backup and rollback remain supported. Added menu and legacy-removal tests.

## 0.3.1 - 2026-10-11

- Added a Scripts-menu program updater. Downloads selector, navigation helper and updater from one pinned GitHub commit, verifies checksums and syntax, and backs up/replaces only program files.
- Saved profiles, active maps and selector undo history remain untouched, including customised bundled profiles. Failed installs attempt rollback; repeat updates do not create extra backups.
- Offline `install.sh --program-only` option, one-time updater bootstrap instructions, program checksum manifest and updater integration tests.

## 0.3.0 - 2026-10-11

- D-pad up/down and Start navigation for profile selection, USB mode choice, capture, undo and finishing. Keyboard arrows/Enter/Esc remain available.
- Bundled static ARMv7 helper reads raw receiver events independently of the active mapping, filters composite/IMU interfaces, temporarily grabs the gamepad, handles reconnects and suppresses held/repeated confirmation presses.
- Original numbered keyboard menu remains the fallback when the helper cannot run or input is piped. CLI commands and mapping operations retain their existing behavior.
- Installer checks the helper checksum and backs up an older helper. Added source, build script and native terminal/input tests.

Controller navigation awaits testing with physical pads on MiSTer.

## 0.2.0 - 2026-10-10

- Separate XInput (`2dc8:3106`) profiles for Xbox, N64 with 8BitDo mod and Stadia, each with captured global and N64 maps. Existing Switch profiles remain supported.
- Automatic USB mode detection from the gamepad interface, ignoring keyboard, mouse and IMU interfaces. Offline menu mode choice and explicit `--mode switch|xinput` commands.
- Independent selection records, backups and undo for each mode, with a shared write lock. Restore supports an originally empty map set and rejects missing backup directories.
- Installer includes both sets of profiles. Advanced maps are explicitly excluded from selector operations.
- Documented hardware results: Xbox XInput rumble works; N64-mod CLI tests and Stadia core tests produced no rumble. The N64 pad remains in S Bluetooth mode with XInput output from the adapter.
- Expanded automated tests for mode isolation, detection, offline selection, undo and failure recovery.

The updated selector awaits a hardware switching test. Controller-operated menus and automatic pairing prompts are still planned.

## 0.1.0 - 2026-10-10

- Keyboard-operated Scripts menu and SSH commands.
- Captured N64 with 8BitDo mod, Stadia and Xbox profiles, each with global and N64 core maps.
- Verified backups before replacing active maps; removal of stale core overrides for the receiver.
- Recovery after failed/interrupted map installation, profile capture and undo of the last profile selection.
- Portable installer that preserves active maps and refuses conflicting existing profiles.
- Hardware confirmation of the Scripts menu and switching from Xbox maps to the N64-pad profile on MiSTer Multisystem 2.

PS4, controller-operated menus and automatic prompts are not included in this version.
