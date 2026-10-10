# Changelog

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
