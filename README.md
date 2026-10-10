# MisterFPGA 8BitDo Selector

Choose the controller paired with an 8BitDo USB Wireless Adapter 2 and restore its saved MiSTer button mappings.

The receiver presents the same USB identity for different paired controllers. This selector lets you choose the physical controller yourself, then applies the corresponding main-menu and core maps.

## Included profiles

| Controller | Main-menu map | N64 core map |
| --- | --- | --- |
| N64 controller with 8BitDo Bluetooth mod | Included | Included |
| Google Stadia | Included | Included |
| Xbox | Included | Included |
| PS4 | Not captured yet | Not captured yet |

All six included maps were captured through the receiver in Switch mode (`057e:2009`). They are actual binary MiSTer v3 mapping files, not templates. The Stadia and Xbox main-menu maps are identical; their N64 maps differ.

## Requirements

- MiSTer with Bash and its usual shell utilities.
- 8BitDo Adapter 2 in Switch mode, presenting as `057e:2009`.
- Standard VID/PID mapping filenames. Per-port unique mapping configurations are not supported by this version.
- A keyboard for the initial menu. It also works over SSH. Controller navigation and automatic prompting are not implemented yet.

## Install on another MiSTer

1. Download this repository as a ZIP using GitHub's **Code > Download ZIP**.
2. Extract it on your computer and copy the extracted project folder to MiSTer using WinSCP or another file transfer tool.
3. Over SSH, change into that folder and run:

```bash
bash install.sh
```

The installer copies the selector into `/media/fat/Scripts/` and the profiles into `/media/fat/config/8bitdo-profiles/`. It does not apply a profile. If a profile already exists with different maps, installation stops before writing anything. An existing different selector is backed up before replacement.

## Use

1. Open **Scripts > 8BitDo_Controller_Selector** from MiSTer's menu, or run:

```bash
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh
```

2. Use a keyboard to choose **N64**, **Stadia** or **Xbox**, then press Enter.
3. Exit the script and pair the selected controller with Adapter 2.
4. Press a button in the core to assign the player, if needed.

MiSTer caches loaded mappings. Re-pairing when changing controllers provides the reconnect step in the tested setup. If the same controller stays connected while you change profiles, turn it off and reconnect it. If the input device remains present, unplug/replug the receiver.

The recorded "last selected" profile is a saved label. It does not identify which controller is currently connected.

## Other cores and additional profiles

Try a core's default layout first. If it needs changes:

1. Select the profile for the controller you are using.
2. Map its buttons inside the core and test them.
3. Return to the selector and choose **Capture current maps into a profile**.
4. Enter that controller's profile name and confirm with `yes`.

Capture saves all active global/core `*input_057e_2009_v3.map` files into that profile. It backs up the previous profile. Make sure the right profile is active before remapping, otherwise maps from another controller could be captured with it.

PS4 can be added by configuring it and capturing the `ps4` profile. Until then, selecting PS4 reports a missing profile and leaves active maps alone.

## Backups and undo

Switching backs up the current receiver maps, verifies staged copies, removes stale receiver core overrides, then installs the selected maps. Other device IDs are left alone. Failed/interrupted file operations attempt to restore the previous map set.

Backups are retained under `/media/fat/config/8bitdo-profiles/backup-*`. Choose **Undo last selector switch** to restore the maps active before the most recent successful selection. Profile capture backups are retained separately and do not change the undo pointer.

The selector manages only standard `*input_057e_2009_v3.map` files. Advanced maps, keyboard maps, other receivers, boot settings and services are outside its scope. A genuine Switch Pro controller using the same VID/PID shares these standard mapping filenames too.

## SSH commands

```bash
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh status
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh apply n64
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh capture n64 --yes
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh restore
```

## Validation and limits

- All six included map files are 128 bytes and were captured after configuring the corresponding controller. N64 and Stadia controls were confirmed; the reverse switch back to Xbox is not yet confirmed.
- The Scripts screen and Xbox-to-N64 profile switch were tested on a Heber MiSTer Multisystem 2.
- Local tests cover switching, stale override removal, other-device preservation, capture, undo, malformed/missing profiles, lock contention and rollback after a simulated installation failure.
- Portability to another MiSTer has not yet been tested on hardware. Other cores, receiver modes and PS4 are not validated.

Version: **0.1.0**. This is a manual Scripts selector, not a change to MiSTer's native OSD menu.

Run the repeatable file-operation checks on a computer with Bash and Python 3:

```bash
python3 tests/test_selector.py
```

Tests use temporary directories and never write to a real MiSTer configuration.

## Planned improvements

- Controller navigation for the selector menu.
- A controller-selection prompt when the receiver's gamepad input appears, with the motion-sensor interface ignored. Integration with MiSTer's display and input handling still needs investigation.
- PS4 mappings once a controller is available for capture and testing.
- More core mappings and a second-MiSTer portability test.

## Reporting a problem

Open an issue with the controller model, adapter mode/firmware, MiSTer kernel version (`uname -r`), selected profile, affected core and steps to reproduce. Include the selector's error output and its `status` output if relevant. Do not include passwords or a full login transcript.
