# MisterFPGA 8BitDo Selector

Choose the controller paired with an **8BitDo USB Wireless Adapter 2** and apply its saved MiSTer button mappings.

The receiver presents the same USB identity for different paired controllers within a USB output mode. MiSTer therefore shares their mapping filenames. This script asks you to choose the physical controller and installs its main-menu and core maps.

**Version 0.3.3 has controller navigation and Update selector in one main Scripts entry, with XInput and Switch output modes.** Use the D-pad to move and Start to select, including capture and undo prompts. It detects the receiver's USB mode, not the paired controller. Automatic prompting on pairing is still planned.

## Included profiles and test results

Each included profile contains a main-menu map and an N64 core map. All 14 maps are actual 128-byte MiSTer v3 files captured on a MiSTer Multisystem 2.

| Controller | Switch maps (`057e:2009`) | XInput maps (`2dc8:3106`) | XInput rumble in this setup |
| --- | --- | --- | --- |
| N64 controller with 8BitDo Bluetooth mod | Included | Included, controls tested | No response to CLI strong/weak rumble tests |
| Google Stadia | Included | Included, controls tested | No rumble observed in the core test |
| Xbox | Included | Included, controls tested | Working in the N64 core |
| PS4 DualShock 4 | Not captured | Included, menu and N64 controls tested | Working in the N64 core |

These are results from this receiver/controller setup, not a claim that every controller model or firmware behaves the same way. The modified N64 pad pairs in **S Bluetooth mode** while the receiver presents **XInput** to MiSTer. The pad's Bluetooth mode and the receiver's USB output mode are separate settings.

## N64 controller layout

The Xbox and Stadia XInput profiles use the layout shown below. Both triggers are mapped to N64 Z; the right stick supplies the four C buttons.

![N64 XInput controller layouts for Google Stadia and Xbox, with labelled controls and shoulder mappings](docs/images/n64-xinput-layout.png)

[Open the full-size layout sheet](docs/images/n64-xinput-layout.png).

The tested DS4 XInput profile uses the same map bytes as Stadia: Cross = N64 A, Square = N64 B, L2/R2 = Z, L1/R1 = L/R, left stick = analog, right stick = C directions, and Options = Start. The sheet above illustrates Xbox and Stadia only.

## Requirements

- MiSTer with Bash and its usual shell utilities.
- An 8BitDo Adapter 2 presenting as `057e:2009` (Switch) or `2dc8:3106` (XInput).
- Standard VID/PID mapping filenames. Per-port unique mapping configurations are not supported.
- A paired pad with a D-pad and Start button for controller navigation. A keyboard or SSH connection provides a fallback.

Switch and XInput profiles use different input layouts. **Do not rename a Switch map to make it an XInput map.** Configure and capture each mode separately.

## First installation

1. Download this repository using GitHub's **Code > Download ZIP**.
2. Extract it and copy the project folder to MiSTer using WinSCP or another file transfer tool.
3. Over SSH, change into that folder and run:

```bash
bash install.sh
```

The installer copies the selector and its bundled ARM helper into `/media/fat/Scripts/` and profiles into `/media/fat/config/8bitdo-profiles/`. It preserves active maps and backs up an existing different selector before replacing it. It checks all bundled profiles first and stops if an existing bundled map differs. Preserve or move the conflicting map before retrying; custom additional core maps are retained.

For an existing installation with customised profiles, use **Update selector** or `bash install.sh --program-only` instead of the full installer. The program-only update does not need those profiles to match the bundled copies.

Existing v0.1.0 Switch profiles stay in their original directories. XInput profiles are installed separately:

```text
config/8bitdo-profiles/n64/
config/8bitdo-profiles/stadia/
config/8bitdo-profiles/xbox/
config/8bitdo-profiles/xinput/n64/
config/8bitdo-profiles/xinput/stadia/
config/8bitdo-profiles/xinput/xbox/
config/8bitdo-profiles/xinput/ps4/
```

## Updating the program

Open **Scripts > 8BitDo_Controller_Selector**, then choose **Update selector**.
Use D-pad up/down and Start, or option **7** in the numbered keyboard menu.
It downloads the latest selector and controller navigation helper from `main`.
Updating also works from the offline USB-mode screen, without choosing a mode.
It pins all downloads to one commit, checks their SHA-256 hashes and shell
syntax, backs up the installed program files, then replaces them. A failed
or interrupted installation attempts to restore the previous files.

**Updates preserve every saved profile, active map and selector undo record.**
Customising a bundled profile does not block a program update. Updates do
not install new profiles or change existing ones. The original full installer
still checks bundled profile conflicts.

From SSH:

```bash
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh update --no-pause
```

If you already installed v0.3.1, run its existing updater once to get this
version. The old updater entry is removed on the next built-in update
(or when the compatibility entry is run again). Its files are backed up.
New installations show only the main selector in Scripts.

For older versions without any updater, download the main script to a
scratch file and run its update command:

```bash
curl -fL --proto '=https' https://raw.githubusercontent.com/Soopahfly/MisterFPGA-8BitDo-Selector/main/Scripts/8BitDo_Controller_Selector.sh -o /tmp/8BitDo_Controller_Selector.sh
bash /tmp/8BitDo_Controller_Selector.sh update --no-pause
```

Run the second command only if the download succeeds. This installs program files only; a first installation still needs the full installer to obtain the bundled profiles. Internet access and
`curl` are required for online updates. There is no background update service.
The repository retains a small compatibility bridge for old updaters. It is
verified during downloads but not installed by the built-in updater.
Checksums detect download corruption; the package and manifest are obtained
from the same repository over HTTPS.

For an offline update, download/extract the latest ZIP and run inside its folder:

```bash
bash install.sh --program-only
```

This uses the same verified updater without downloading or checking profiles.
`UPDATE_SOURCE_DIR=/path/to/extracted/project` supplies a local package directly.
Program backups are stored in `config/8bitdo-profiles/program-backup-*/` with
paths relative to `/media/fat`. If already current, no new backup is made.
The built-in updater shares the selector/installer lock. Updates from Scripts can be
finished with Start on a paired pad, or Enter on a keyboard.

### Certificate errors (curl 60 or 77)

The updater automatically uses a readable, nonempty `/media/fat/cacert.pem` when present.
Download the [Mozilla CA bundle](https://curl.se/ca/cacert.pem) on a PC,
save it as `cacert.pem`, and copy it into `\\mister\sdcard\` using SMB
(or into `/media/fat/` using SFTP). Keep the file there for future updates.

The updater passes this bundle explicitly to curl for every download and
ignores `~/.curlrc`, so SSH and Scripts-menu updates use the same TLS options.
There is no need to edit system certificates or curl configuration.
If the bundle is absent, curl uses its normal CA store and supported environment settings.
An invalid supplied bundle fails the update; verification is never disabled.
Check the MiSTer clock too if verification fails with a current bundle.

To use another trusted bundle over SSH:

```bash
SELECTOR_CA_BUNDLE=/path/to/cacert.pem \
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh update --no-pause
```

For an older installed selector, use this one-time verified bootstrap:

```bash
curl -q --cacert /media/fat/cacert.pem -fL --proto '=https' \
  https://raw.githubusercontent.com/Soopahfly/MisterFPGA-8BitDo-Selector/main/Scripts/8BitDo_Controller_Selector.sh \
  -o /tmp/8BitDo_Controller_Selector.sh &&
bash /tmp/8BitDo_Controller_Selector.sh update --no-pause
```

The bundle must come from a trusted download on another device; the selector
does not fetch or replace CA certificates. If HTTPS remains unavailable, use
the offline program-only installation described above.

## Use

1. Pair your controller and open **Scripts > 8BitDo_Controller_Selector**, or run:

```bash
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh
```

2. The script detects the receiver's USB mode from its gamepad input. If disconnected or ambiguous, choose the mode matching the adapter's USB output.
3. Use **D-pad up/down** to highlight **N64**, **Stadia**, **Xbox** or **PS4**, then press **Start**. Keyboard arrows and Enter also work. Choose Exit to cancel, or press Esc on the keyboard.
4. Exit the script, turn the controller off and reconnect it. Press a button in the core to assign the player, if needed.

You can also select a profile before pairing. Choosing a mode in this script selects saved mapping files; it does **not** change the adapter's hardware mode.

MiSTer caches loaded mappings. Re-pairing when changing controllers provides the reconnect step in the tested setup. If the input device remains present after switching the pad off, unplug/replug the receiver.

The recorded **last selected** profile is a saved label for that USB mode. It does not identify the connected physical controller. The receiver's keyboard, mouse and Switch IMU interfaces are ignored during mode detection.

## Controller navigation

The menu reads the receiver's raw Linux input events. It does not depend on the MiSTer profile currently applied. Start is used for selection because the N64 mod and Xbox/Stadia face buttons have different raw layouts. Analogue sticks and face buttons do not navigate this version.

You can use the working pad to open Scripts, select the next pad's profile, finish with Start, then turn the old pad off and pair the new one. You can also navigate with the newly paired pad even when its MiSTer mappings are wrong, provided you can open the script using a keyboard or SSH.

The helper discovers the gamepad interface dynamically, ignores the receiver's keyboard/mouse and Switch IMU interfaces, and rechecks for a reconnected receiver. It temporarily grabs the gamepad while a menu is open to keep those presses out of MiSTer, and releases it on exit. A held Start button must be released and pressed again before accepting the next screen. An unavailable or busy gamepad leaves keyboard controls available.

The bundled helper is a static ARMv7 hard-float executable in `Scripts/.8bitdo-selector/controller-menu`. No compiler, Python or extra packages are needed on MiSTer. Install the whole package to get it. If the helper is missing or cannot run, the selector falls back to its numbered keyboard menu. SSH arrow/Enter controls also work; a non-interactive/piped session retains the original numbered interface. `NAV_HELPER=/path/to/helper` overrides the helper for development.

## Other cores and additional profiles

Try the default layout first. [The core-mapping guide](docs/CORE-MAPPING.md) explains good next targets: Saturn, six-button Mega Drive, Neo Geo and PSX. These are configuration candidates; only N64 core maps are currently bundled.

If a core needs changes:

1. Apply the correct profile and reconnect the controller.
2. Map its buttons inside that core and test them.
3. Return to the selector and choose **Capture current maps into a profile**.
4. Select the controller, then choose **Save current maps**. In the keyboard-only fallback, enter `n64`, `stadia`, `xbox` or `ps4` and confirm with `yes`.

**Capture before applying another controller profile.** Applying replaces the active standard map set, including removal of core maps absent from the selected saved profile.

Capture saves the active standard global/core v3 maps for the selected USB mode and backs up the previous profile. Make sure the correct profile is active before remapping, otherwise another controller's core maps could be captured with it. Capture does not change the active maps or the undo pointer.

The included DualShock 4 profile is for XInput only. Its global and N64 maps are byte-for-byte identical to the Stadia profile, and menu controls, N64 buttons/sticks and physical rumble were verified with the DS4 paired. No PS4 Switch-mode profile has been captured.

For the main menu's SNES-style button prompts, Stadia/Xbox physical positions are: MiSTer B = physical A, A = B, Y = X, X = Y. Core-specific mappings are configured separately.

Want to share your mappings? See [CONTRIBUTING.md](CONTRIBUTING.md) for files to submit, an issue/PR workflow and the test record. Core emulation settings such as PSX pad type or Mega Drive six-button mode are not included in these `.map` profiles.

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
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh update --no-pause
```

When disconnected, specify the mode before the command:

```bash
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh --mode xinput apply xbox
bash /media/fat/Scripts/8BitDo_Controller_Selector.sh --mode switch status
```

An explicit mode conflicting with a single detected mode is rejected. If both identities are present, automatic commands stop and require an explicit mode. The selector cannot distinguish multiple receivers or a genuine controller sharing the same identity.

## Validation and limits

- Switch Scripts-menu operation and an Xbox-to-N64 profile switch were tested on MiSTer Multisystem 2 with v0.1.0.
- All four XInput controllers were configured and tested on the same machine. Xbox and DualShock 4 rumble worked in N64; N64-mod and Stadia tests did not produce rumble.
- Current selector checks cover both USB modes, detection, offline menus, stale override removal, independent undo, capture, preservation of other-device/advanced maps, missing/corrupt profiles, installer conflicts, locks and simulated failure rollback.
- The built-in updater passes local/mocked HTTPS tests for profile preservation, checksum/download rejection, commit pinning, repeat updates, rollback and v0.3.1 migration. Real GitHub downloads and legacy-entry backup/removal were also checked on a development machine. Online checking was confirmed on MiSTer with a supplied CA bundle and v0.3.2. The v0.3.3 automatic-bundle change still needs its hardware update test.
- Controller navigation passes native terminal and input-translation tests, but the bundled ARM helper and physical D-pad/Start operation still need testing on MiSTer. The updated selector still needs a hardware switching test. Portability to a second MiSTer and other cores remain untested. DS4 profile switching and controller-menu navigation still need a hardware test.

Run the checks on a Linux computer with Bash, Python 3 and GCC (for the native navigation tests):

```bash
python3 tests/test_selector.py
python3 tests/test_navigation.py
python3 tests/test_updater.py
```

Tests use temporary directories and never write to a real MiSTer configuration.

To rebuild the bundled helper on a Linux development machine with an ARM hard-float musl cross toolchain (including Linux headers) installed:

```bash
bash src/build.sh
```

The default tools are `arm-linux-musleabihf-gcc` and `arm-linux-musleabihf-strip`; override them with `CC` and `STRIP`. `CPPFLAGS` can supply a Linux header path when building a musl wrapper toolchain. The build script updates the binary checksum checked by the installer. After changing any distributed program file, run `bash update/build-manifest.sh` to refresh the updater manifest. The helper source is in `src/controller-menu.c`.

The bundled helper links musl 1.2.4 and GCC 13 runtime code. Their notices are in `src/licenses/`; build details are in `src/BUILD.md`.

## Planned improvements

- A selection prompt when the receiver's gamepad input appears. Integration with MiSTer's display and input handling still needs investigation.
- More core mappings, PS4 Switch-mode mappings and a second-MiSTer portability test.

## Reporting a problem

Open an issue with the controller model, adapter mode/firmware, MiSTer kernel (`uname -r`), selected profile, affected core and steps to reproduce. Include the selector's error and `status` output. Do not include passwords or a full login transcript.
