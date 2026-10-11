# Contributing controller profiles

Submit a pull request, or open a GitHub issue and attach an archive of your
map files. Maintainers can place issue attachments into the repository after
review. Do not upload ROMs, BIOS files, login transcripts or backups.

## Configure and test

1. Use a supported receiver USB output mode: XInput `2dc8:3106`, or Switch
   `057e:2009`. Keep maps for each mode separate. Changing a filename does not
   convert a map between modes.
2. Apply the saved profile for the physical pad you are configuring, then
   reconnect. For a new PS4 profile, pair and define the main-menu controls
   first, configure/test the core, then capture as PS4.
3. Configure any additional core controls, test every required button/axis,
   and use **Capture current maps** before switching to another profile.
4. Test switching away and back, including the reconnect step. See
   [the core-mapping guide](docs/CORE-MAPPING.md).

The currently selectable profile IDs are `n64`, `stadia`, `xbox` and `ps4`.
A different controller model needs a code/menu addition as well as map files.
Do not silently replace an existing profile with a different model's mapping.

## Files to submit

Download only the top-level `.map` files from the saved profile folder:

| Mode | Example Xbox profile folder | Required main-menu filename |
| --- | --- | --- |
| XInput | `/media/fat/config/8bitdo-profiles/xinput/xbox/` | `input_2dc8_3106_v3.map` |
| Switch | `/media/fat/config/8bitdo-profiles/xbox/` | `input_057e_2009_v3.map` |

For a pull request, place files under the corresponding
`config/8bitdo-profiles/` directory in this repository. Include the generated
core maps you tested, preserving their filenames. Each supported file must
be a regular 128-byte standard v3 map. Exclude backup/work directories,
`last-selected`, `last-backup`, advanced maps and maps for other USB IDs.

Use a ZIP or tar archive for issue attachments, keeping each controller/mode
in a clearly named folder. Add a simple physical-button layout table, or a
labelled controller image, so another person can check the intended controls.

## Include this test record

```text
Physical controller model and revision:
Adapter 2 firmware (or unknown):
Receiver USB mode and VID:PID:
Pad Bluetooth pairing mode, if relevant:
MiSTer kernel (uname -r):
Core names and build versions:
Games or controller-test programs used:
Buttons/axes tested:
Rumble: working / no response / not tested (state core or CLI test):
Switch-away/back and reconnect test:
Differences from any existing profile:
Known limitations or untested controls:
```

A Linux force-feedback capability or successful effect upload alone does not
prove physical rumble. Record what the controller actually did. Mark untested
features as untested.

## Program updates versus profile additions

The built-in **Update selector** downloads program files only. It will not
replace local profiles or install a newly contributed core map. Document any
new map's installation separately. Back up an existing local map before copying
an approved replacement into a saved profile folder, then select that profile
and reconnect to use it. Adding a new core map does not require recapturing the
other existing maps.

The full installer refuses conflicting bundled profiles. Use
`bash install.sh --program-only` when updating code on a machine with custom
profiles; do not delete those profiles to get past the full installer.

## Code and documentation changes

Run the relevant checks on Linux:

```bash
python3 tests/test_selector.py
python3 tests/test_navigation.py
python3 tests/test_updater.py
```

Navigation tests also need GCC. Tests use isolated temporary directories.
For program changes, update the changelog and run
`bash update/build-manifest.sh`. If rebuilding the ARM helper, follow
[src/BUILD.md](src/BUILD.md), update its checksum and then refresh the program
manifest. Documentation-only edits do not require a manifest rebuild.

State clearly which checks were automated and which used physical MiSTer
hardware. The repository keeps the legacy updater bridge and v0.3.1 test
fixture to verify migration; the bridge is not a second menu entry on a new
installation.
