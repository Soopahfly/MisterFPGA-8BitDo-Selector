# MisterFPGA 8BitDo Selector

Choose the controller paired with an **8BitDo USB Wireless Adapter 2** and apply its saved MiSTer button mappings.

The receiver presents the same USB identity for different paired controllers within a USB output mode. MiSTer therefore shares their mapping filenames. This script asks you to choose the physical controller and installs its main-menu and core maps.

**Version 0.2.0 supports XInput and Switch output modes.** It runs from MiSTer's Scripts menu or over SSH, using a keyboard. It detects the receiver's USB mode, not the paired controller. Automatic prompting on pairing and controller-operated menus are still planned.

## Included profiles and test results

Each included profile contains a main-menu map and an N64 core map. All 12 maps are actual 128-byte MiSTer v3 files captured on a MiSTer Multisystem 2.

| Controller | Switch maps (`057e:2009`) | XInput maps (`2dc8:3106`) | XInput rumble in this setup |
| --- | --- | --- | --- |
| N64 controller with 8BitDo Bluetooth mod | Included | Included, controls tested | No response to CLI strong/weak rumble tests |
| Google Stadia | Included | Included, controls tested | No rumble observed in the core test |
| Xbox | Included | Included, controls tested | Working in the N64 core |
| PS4 | Not captured | Not captured | Not tested |

These are results from this receiver/controller setup, not a claim that every controller model or firmware behaves the same way. The modified N64 pad pairs in **S Bluetooth mode** while the receiver presents **XInput** to MiSTer. The pad's Bluetooth mode and the receiver's USB output mode are separate settings.

## Requirements

- MiSTer with Bash and its usual shell utilities.
- An 8BitDo Adapter 2 presenting as `057e:2009` (Switch) or `2dc8:3106` (XInput).
- Standard VID/PID mapping filenames. Per-port unique mapping configurations are not supported.
- A keyboard for the menu, or an SSH connection.

Switch and XInput profiles use different input layouts. **Do not rename a Switch map to make it an XInput map.** Configure and capture each mode separately.

## Install or update

1. Download this repository using GitHub's **Code > Download ZIP**.
2. Extract it and copy the project folder to MiSTer using WinSCP or another file transfer tool.
3. Over SSH, change into that folder and run:

```bash
bash install.sh
```

The installer copies the selector into `/media/fat/Scripts/` and profiles into `/media/fat/config/8bitdo-profiles/`. It preserves active maps and backs up an existing different selector before replacing it. It checks all bundled profiles first and stops if an existing bundled map differs. Preserve or move the conflicting map before retrying; custom additional core maps are retained.

Existing v0.1.0 Switch profiles stay in their original directories. XInput profiles are installed separately:

```text
config/8bitdo-profiles/n64/
config/8bitdo-profiles/stadia/
config/8bitdo-profiles/xbox/
config/8bitdo-profiles/xinput/n64/
config/8bitdo-profiles/xinput/stadia/
config/8bitdo-profiles/xinput/xbox/
```

## Use

1. Pair your controller and open **Scripts > 8BitDo_Controller_Selector**, or run:

```bash
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh
```

2. The script detects the receiver's USB mode from its gamepad input. If disconnected or ambiguous, choose the mode matching the adapter's USB output.
3. Choose **N64**, **Stadia** or **Xbox** with the keyboard, then press Enter.
4. Exit the script, turn the controller off and reconnect it. Press a button in the core to assign the player, if needed.

You can also select a profile before pairing. Choosing a mode in this script selects saved mapping files; it does **not** change the adapter's hardware mode.

MiSTer caches loaded mappings. Re-pairing when changing controllers provides the reconnect step in the tested setup. If the input device remains present after switching the pad off, unplug/replug the receiver.

The recorded **last selected** profile is a saved label for that USB mode. It does not identify the connected physical controller. The receiver's keyboard, mouse and Switch IMU interfaces are ignored during mode detection.

## Other cores and additional profiles

Try the default layout first. If a core needs changes:

1. Apply the correct profile and reconnect the controller.
2. Map its buttons inside that core and test them.
3. Return to the selector and choose **Capture current maps into a profile**.
4. Enter `n64`, `stadia`, `xbox` or `ps4`, then confirm with `yes`.

Capture saves the active standard global/core v3 maps for the selected USB mode and backs up the previous profile. Make sure the correct profile is active before remapping, otherwise another controller's core maps could be captured with it. Capture does not change the active maps or the undo pointer.

PS4 can be added when a pad is available for configuration and testing. Until then, selecting PS4 reports a missing profile and leaves active maps alone.

For the main menu's SNES-style button prompts, Stadia/Xbox physical positions are: MiSTer B = physical A, A = B, Y = X, X = Y. Core-specific mappings are configured separately.

## Backups and undo

Applying a profile backs up the active maps for that USB mode, verifies staged copies, removes stale standard core overrides for that identity, then installs the selected maps. Failed/interrupted map installation attempts to restore the previous map set. Undo also handles an originally empty map set.

| USB mode | Profiles, state and backups |
| --- | --- |
| Switch | `/media/fat/config/8bitdo-profiles/` |
| XInput | `/media/fat/config/8bitdo-profiles/xinput/` |

Choose **Undo last selector switch** to restore the maps active before the last successful selection in the current mode. Switch and XInput have independent undo pointers. Both modes and the installer share a lock to prevent concurrent writes. Capture backups do not replace the undo pointer.

Only standard global/core v3 maps for the selected identity are managed. Advanced maps, keyboard maps, other USB identities, boot settings and services are left alone. Other hardware with the same VID/PID also shares those filenames, including genuine Switch Pro controllers in Switch mode and other 8BitDo devices presenting as `2dc8:3106`.

## SSH commands

With a paired receiver, USB mode is detected automatically:

```bash
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh status
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh apply n64
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh capture n64 --yes
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh restore
```

When disconnected, specify the mode before the command:

```bash
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh --mode xinput apply xbox
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh --mode switch status
```

An explicit mode conflicting with a single detected mode is rejected. If both identities are present, automatic commands stop and require an explicit mode. The selector cannot distinguish multiple receivers or a genuine controller sharing the same identity.

## Validation and limits

- Switch Scripts-menu operation and an Xbox-to-N64 profile switch were tested on MiSTer Multisystem 2 with v0.1.0.
- All three XInput controllers were configured and tested on the same machine. Xbox rumble worked; N64-mod and Stadia tests did not produce rumble.
- The v0.2.0 selector passes local file-operation tests for both modes, mode detection, offline menu choice, stale override removal, independent undo, capture, other-device and advanced-map preservation, missing/corrupt profiles, installer conflicts, locks and simulated failure rollback.
- The updated selector still needs a hardware switching test. Portability to a second MiSTer, other cores and PS4 remain untested.

Run the checks on a computer with Bash and Python 3:

```bash
python3 tests/test_selector.py
```

Tests use temporary directories and never write to a real MiSTer configuration.

## Planned improvements

- Controller navigation for the selector menu.
- A selection prompt when the receiver's gamepad input appears. Integration with MiSTer's display and input handling still needs investigation.
- PS4 mappings, more core mappings and a second-MiSTer portability test.

## Reporting a problem

Open an issue with the controller model, adapter mode/firmware, MiSTer kernel (`uname -r`), selected profile, affected core and steps to reproduce. Include the selector's error and `status` output. Do not include passwords or a full login transcript.
