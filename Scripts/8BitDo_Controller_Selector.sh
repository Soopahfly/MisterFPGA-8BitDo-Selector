#!/bin/bash
# 8BitDo Controller Selector v0.3.2 for MiSTer
# Install in /media/fat/Scripts/. Existing profiles live in
# Switch profiles: config/8bitdo-profiles/{n64,stadia,xbox,ps4}/.
# XInput profiles: config/8bitdo-profiles/xinput/{n64,stadia,xbox,ps4}/.
# D-pad up/down and Start. Keyboard arrows/Enter, or numbered fallback.
# Also works over SSH.
# After APPLY/RESTORE, exit the script, turn the pad off, wait for its
# input device to disappear, then reconnect. MiSTer caches loaded maps.
# Scope: standard v3 maps for the selected USB mode. Other devices,
# advanced maps, keyboard maps, boot settings and services are untouched.
# CLI: [--mode auto|switch|xinput] status | apply PROFILE | capture PROFILE --yes | restore
# Update: update [--no-pause], requires no paired receiver.
# capture requires explicit confirmation in the menu, or --yes on the CLI.
# CONFIG_ROOT override is for isolated tests or alternate config locations.

set -eu
umask 077
CONFIG_ROOT=${CONFIG_ROOT:-/media/fat/config}
INPUTS="$CONFIG_ROOT/inputs"
PROFILE_ROOT="$CONFIG_ROOT/8bitdo-profiles"
LOCK="$PROFILE_ROOT/.selector-lock"
MODE=${RECEIVER_MODE:-auto}
INPUT_DEVICES=${INPUT_DEVICES:-/proc/bus/input/devices}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
NAV_HELPER=${NAV_HELPER:-$SCRIPT_DIR/.8bitdo-selector/controller-menu}
NAV_AVAILABLE=0
# CLI and piped sessions retain the original keyboard/command interface.
if [ -t 0 ] && [ -t 1 ] && [ -x "$NAV_HELPER" ] && "$NAV_HELPER" --check >/dev/null 2>&1; then
    NAV_AVAILABLE=1
fi
WORK=
ROLLBACK=
TARGET=

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
label() {
    case "$1" in
        n64) printf 'N64 (8BitDo mod)' ;;
        stadia) printf 'Stadia' ;;
        xbox) printf 'Xbox' ;;
        ps4) printf 'PS4' ;;
        *) die 'Unknown profile. Use n64, stadia, xbox or ps4.' ;;
    esac
}
valid_maps() {
    local directory=$1 file count=0 size
    [ -d "$directory" ] && [ ! -L "$directory" ] || die "Missing regular map directory: $directory"
    [ "${2:-profile}" = backup ] || [ -f "$directory/$GLOBAL" ] || die "Missing main-menu map: $directory/$GLOBAL"
    for file in "$directory"/*input_${IDENTITY}_v3.map; do
        [ -e "$file" ] || continue
        case "${file##*/}" in *_advanced_input_*) continue ;; esac
        [ -f "$file" ] && [ ! -L "$file" ] || die "Not a regular map: $file"
        size=$(wc -c < "$file")
        [ "$size" -eq 128 ] || die "Expected a 128-byte v3 map: $file ($size bytes)"
        count=$((count + 1))
    done
    [ "${2:-profile}" = backup ] || [ "$count" -gt 0 ] || die "No maps in $directory"
}
copy_maps() {
    local source=$1 destination=$2 file
    for file in "$source"/*input_${IDENTITY}_v3.map; do
        [ -e "$file" ] || continue
        case "${file##*/}" in *_advanced_input_*) continue ;; esac
        [ -f "$file" ] && [ ! -L "$file" ] || return 1
        cp -p "$file" "$destination/" || return 1
    done
}
remove_maps() {
    local directory=$1 file
    for file in "$directory"/*input_${IDENTITY}_v3.map; do
        [ -e "$file" ] || continue
        case "${file##*/}" in *_advanced_input_*) continue ;; esac
        rm -- "$file" || return 1
    done
}
cleanup() {
    local rc=$?
    trap - EXIT HUP INT TERM
    if [ -n "$ROLLBACK" ]; then
        printf 'Restoring maps after an interrupted or failed operation...\n' >&2
        if remove_maps "$TARGET" && copy_maps "$ROLLBACK" "$TARGET"; then
            printf 'Previous maps restored.\n' >&2
        else
            printf 'Recovery needed: copy maps from %s into %s\n' "$ROLLBACK" "$TARGET" >&2
            rc=1
        fi
    fi
    [ -z "$WORK" ] || rm -rf -- "$WORK"
    rmdir "$LOCK" 2>/dev/null || true
    exit "$rc"
}
lock() {
    mkdir -p "$PROFILE_ROOT" "$PROFILES"
    mkdir "$LOCK" 2>/dev/null || die "Another selector is running (lock: $LOCK)."
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    WORK=$(mktemp -d "$PROFILES/.work-XXXXXX")
}
backup_maps() {
    local source=$1 file
    BACKUP=$(mktemp -d "$PROFILES/backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")
    mkdir "$BACKUP/maps"
    copy_maps "$source" "$BACKUP/maps" || die 'Backup failed; no maps changed.'
    # Confirm every backup before allowing replacement.
    for file in "$source"/*input_${IDENTITY}_v3.map; do
        [ -e "$file" ] || continue
        case "${file##*/}" in *_advanced_input_*) continue ;; esac
        cmp -s "$file" "$BACKUP/maps/${file##*/}" || die 'Backup verification failed.'
    done
    if [ -f "$STATE" ]; then cp "$STATE" "$BACKUP/last-selected"; fi
}
replace_maps() {
    local source=$1 destination=$2 file
    mkdir -p "$destination" "$WORK/staged"
    copy_maps "$source" "$WORK/staged" || die 'Staging failed; no maps changed.'
    for file in "$source"/*input_${IDENTITY}_v3.map; do
        [ -e "$file" ] || continue
        case "${file##*/}" in *_advanced_input_*) continue ;; esac
        cmp -s "$file" "$WORK/staged/${file##*/}" || die 'Staging verification failed.'
    done
    backup_maps "$destination"
    TARGET=$destination
    ROLLBACK="$BACKUP/maps"
    remove_maps "$destination" || die 'Could not clear previous receiver maps.'
    for file in "$WORK/staged"/*input_${IDENTITY}_v3.map; do
        [ -e "$file" ] || continue
        case "${file##*/}" in *_advanced_input_*) continue ;; esac
        mv -- "$file" "$destination/" || die 'Could not install map.'
    done
    for file in "$source"/*input_${IDENTITY}_v3.map; do
        [ -e "$file" ] || continue
        case "${file##*/}" in *_advanced_input_*) continue ;; esac
        cmp -s "$file" "$destination/${file##*/}" || die 'Installed map verification failed.'
    done
    ROLLBACK=
}
reload_note() {
    printf '\nMaps saved to disk. To activate them:\n'
    printf 'Exit this script. Turn the pad OFF, wait a few seconds, then reconnect.\n'
    printf 'If the receiver input stays present, unplug/replug the receiver instead.\n'
    printf 'This also resets player assignment; press a button in the core to join.\n'
}
apply_profile() {
    label "$1" >/dev/null
    valid_maps "$PROFILES/$1"
    lock
    replace_maps "$PROFILES/$1" "$INPUTS"
    printf '%s\n' "$1" > "$WORK/state"
    mv "$WORK/state" "$STATE"
    printf '%s\n' "${BACKUP##*/}" > "$WORK/last-backup"
    mv "$WORK/last-backup" "$LAST_BACKUP"
    sync
    printf 'Selected: %s\nBackup: %s\n' "$(label "$1")" "$BACKUP"
    reload_note
}
capture_profile() {
    label "$1" >/dev/null
    valid_maps "$INPUTS"
    lock
    replace_maps "$INPUTS" "$PROFILES/$1"
    sync
    printf 'Captured current receiver maps as %s.\n' "$(label "$1")"
    printf 'Previous profile files backed up in %s\n' "$BACKUP"
    printf 'Capture does not change the active maps or reconnect the controller.\n'
}
restore_backup() {
    [ -f "$LAST_BACKUP" ] || die 'No selector switch to undo yet.'
    local name source
    name=$(cat "$LAST_BACKUP")
    case "$name" in backup-*) ;; *) die 'Invalid backup pointer.' ;; esac
    case "$name" in */*|*..*) die 'Invalid backup pointer.' ;; esac
    source="$PROFILES/$name"
    valid_maps "$source/maps" backup
    lock
    replace_maps "$source/maps" "$INPUTS"
    if [ -f "$source/last-selected" ]; then
        cp "$source/last-selected" "$STATE"
    else
        rm -f "$STATE"
    fi
    # Retain the previous snapshot; restore remains repeatable.
    sync
    printf 'Restored maps from %s\n' "$source"
    reload_note
}
status() {
    local p file
    printf '8BitDo Controller Selector v0.3.2\nReceiver mode: %s (%s)\n' "$MODE" "${IDENTITY/_/:}"
    printf 'Last selected by this script: '
    if [ -f "$STATE" ]; then cat "$STATE"; else printf 'unknown\n'; fi
    printf '(This is a record, not automatic controller detection.)\n\n'
    for p in n64 stadia xbox ps4; do
        printf '%s: ' "$(label "$p")"
        if [ -f "$PROFILES/$p/$GLOBAL" ]; then
            printf 'saved\n'
            for file in "$PROFILES/$p"/*input_${IDENTITY}_v3.map; do
                case "${file##*/}" in *_advanced_input_*) continue ;; esac
                [ -f "$file" ] && printf '  %s\n' "${file##*/}"
            done
        else
            printf 'not captured\n'
        fi
    done
}
# Run updates in a subshell to isolate traps, locks and updater variables.
update_program() (
set -eu
umask 077
DEST=${MISTER_ROOT:-/media/fat}
REPO=Soopahfly/MisterFPGA-8BitDo-Selector
FILES=(Scripts/8BitDo_Controller_Selector.sh Scripts/8BitDo_Selector_Update.sh Scripts/.8bitdo-selector/controller-menu)
PROFILE_ROOT="$DEST/config/8bitdo-profiles"
WORK=
LOCK=
BACKUP=
ROLLBACK=0
PAUSE=1
[ "${1:-}" != --no-pause ] || PAUSE=0
[ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = --no-pause ]; } || { printf 'Usage: %s [--no-pause]\n' "$0" >&2; exit 1; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() {
    local rc=$? file
    trap - EXIT HUP INT TERM
    if [ "$ROLLBACK" = 1 ]; then
        printf 'Update interrupted or failed. Restoring previous program files...\n' >&2
        for file in "${FILES[@]}"; do
            if [ -f "$BACKUP/$file" ]; then
                # Copy to a new file, then rename. Never write over a running executable.
                if cp -p "$BACKUP/$file" "$WORK/recovery" && mv "$WORK/recovery" "$DEST/$file"; then :
                else printf 'Recovery needed: %s -> %s\n' "$BACKUP/$file" "$DEST/$file" >&2; rc=1; fi
            else
                rm -f -- "$DEST/$file" || rc=1
            fi
        done
    fi
    [ -z "$WORK" ] || rm -rf -- "$WORK"
    [ -z "$LOCK" ] || rmdir "$LOCK" 2>/dev/null || true
    if [ "$PAUSE" = 1 ] && [ -t 0 ]; then
        if [ -t 1 ] && [ -x "$DEST/Scripts/.8bitdo-selector/controller-menu" ] &&
           "$DEST/Scripts/.8bitdo-selector/controller-menu" --check >/dev/null 2>&1; then
            "$DEST/Scripts/.8bitdo-selector/controller-menu" --wait 'Updater finished' 'Program update completed or stopped. See the result above.' 'exit|Exit' >/dev/null || true
        else
            printf '\nPress Enter to finish: '
            IFS= read -r answer || true
        fi
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
fetch() {
    curl --proto '=https' --tlsv1.2 --location --fail --silent --show-error \
        --connect-timeout 15 --max-time 120 --retry 2 "$1" -o "$2"
}
[ -d "$DEST" ] || die "MiSTer root does not exist: $DEST"
for command in bash sha256sum mktemp cmp cp mv; do command -v "$command" >/dev/null || die "Missing utility: $command"; done
# UPDATE_SOURCE_DIR provides a local, verified package for offline updates/tests.
if [ -z "${UPDATE_SOURCE_DIR:-}" ]; then
    command -v curl >/dev/null || die 'curl is required for online updates.'
fi
[ ! -L "$DEST/Scripts" ] && [ ! -L "$DEST/Scripts/.8bitdo-selector" ] || die 'Program directories must not be symlinks.'
for directory in "$DEST/Scripts" "$DEST/Scripts/.8bitdo-selector" "$PROFILE_ROOT"; do
    [ ! -e "$directory" ] || [ -d "$directory" ] || die "Not a directory: $directory"
    [ ! -L "$directory" ] || die "Not a regular directory: $directory"
done
for file in "${FILES[@]}"; do
    [ ! -L "$DEST/$file" ] || die "Destination is a symlink: $file"
    [ ! -e "$DEST/$file" ] || [ -f "$DEST/$file" ] || die "Destination is not a file: $file"
done
mkdir -p "$PROFILE_ROOT" "$DEST/Scripts/.8bitdo-selector"
mkdir "$PROFILE_ROOT/.selector-lock" 2>/dev/null || die 'Selector, installer or another updater is running.'
LOCK="$PROFILE_ROOT/.selector-lock"
WORK=$(mktemp -d "$PROFILE_ROOT/.update-XXXXXX")
mkdir "$WORK/staged"
printf 'Checking for an 8BitDo Selector update...\n'
if [ -n "${UPDATE_SOURCE_DIR:-}" ]; then
    cp "$UPDATE_SOURCE_DIR/update/program.sha256" "$WORK/program.sha256" || die 'Cannot read local update manifest.'
    revision='local package'
else
    fetch "https://api.github.com/repos/$REPO/git/ref/heads/main" "$WORK/ref.json" || die 'Could not check GitHub. Program files are unchanged.'
    revision=$(sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' "$WORK/ref.json" | head -n 1)
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || die 'GitHub returned an invalid commit ID.'
    fetch "https://raw.githubusercontent.com/$REPO/$revision/update/program.sha256" "$WORK/program.sha256" || die 'Could not download update manifest.'
fi
# Parse a fixed allowlist, never arbitrary download paths or checksum commands.
count=0
while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^([0-9a-f]{64})\ \ (.+)$ ]] || die 'Invalid program checksum manifest.'
    file=${BASH_REMATCH[2]}
    case "$file" in
        Scripts/8BitDo_Controller_Selector.sh|Scripts/8BitDo_Selector_Update.sh|Scripts/.8bitdo-selector/controller-menu) ;;
        *) die "Unexpected file in update: $file" ;;
    esac
    [ ! -e "$WORK/staged/$file" ] || die 'Duplicate update manifest entry.'
    mkdir -p "$(dirname -- "$WORK/staged/$file")"
    if [ -n "${UPDATE_SOURCE_DIR:-}" ]; then
        [ -f "$UPDATE_SOURCE_DIR/$file" ] && [ ! -L "$UPDATE_SOURCE_DIR/$file" ] || die "Missing regular update file: $file"
        cp "$UPDATE_SOURCE_DIR/$file" "$WORK/staged/$file" || die 'Local update copy failed.'
    else
        fetch "https://raw.githubusercontent.com/$REPO/$revision/$file" "$WORK/staged/$file" || die 'Download failed. Program files are unchanged.'
    fi
    count=$((count+1))
done < "$WORK/program.sha256"
[ "$count" -eq "${#FILES[@]}" ] || die 'Incomplete program update.'
(cd "$WORK/staged" && sha256sum -c "$WORK/program.sha256") || die 'Checksum verification failed. Program files are unchanged.'
for file in "${FILES[@]}"; do
    case "$file" in *.sh) bash -n "$WORK/staged/$file" || die "Invalid shell syntax: $file" ;; esac
    chmod +x "$WORK/staged/$file"
done
changed=0
[ ! -e "$DEST/Scripts/8BitDo_Selector_Update.sh" ] || changed=1
for file in "${FILES[@]}"; do
    [ "$file" != Scripts/8BitDo_Selector_Update.sh ] || continue
    cmp -s "$WORK/staged/$file" "$DEST/$file" || changed=1
done
if [ "$changed" = 0 ]; then
    printf 'Already up to date (%s). Profiles and active maps are unchanged.\n' "$revision"
    exit 0
fi
BACKUP=$(mktemp -d "$PROFILE_ROOT/program-backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")
for file in "${FILES[@]}"; do
    if [ -f "$DEST/$file" ]; then
        mkdir -p "$(dirname -- "$BACKUP/$file")"
        cp -p "$DEST/$file" "$BACKUP/$file"
        cmp -s "$DEST/$file" "$BACKUP/$file" || die 'Backup verification failed. Program files are unchanged.'
    fi
done
printf '%s\n' "$revision" > "$BACKUP/updated-to"
ROLLBACK=1
for file in "${FILES[@]}"; do
    if [ "$file" = Scripts/8BitDo_Selector_Update.sh ]; then
        rm -f -- "$DEST/$file"
    else
        mv "$WORK/staged/$file" "$DEST/$file"
    fi
done
sync
ROLLBACK=0
printf 'Updated selector and navigation helper (%s).\n' "$revision"
printf 'Previous program files: %s\n' "$BACKUP"
printf 'Saved profiles, active maps and selector undo history are unchanged.\n'

)

keyboard_menu() {
    local choice p answer
    status
    printf '\nUse the KEYBOARD: number then Enter.\n'
    printf '1  Select N64\n2  Select Stadia\n3  Select Xbox\n4  Select PS4 (requires saved profile)\n'
    printf '5  Capture current maps into a profile\n6  Undo last selector switch\n7  Update selector\n0  Exit\n\nChoice: '
    IFS= read -r choice || exit 0
    case "$choice" in
        0) exit 0 ;;
        1) apply_profile n64 ;;
        2) apply_profile stadia ;;
        3) apply_profile xbox ;;
        4) apply_profile ps4 ;;
        5)
            printf 'Which paired controller did you just map? (n64/stadia/xbox/ps4): '
            IFS= read -r p || exit 0
            label "$p" >/dev/null
            printf 'Save ALL current receiver v3 maps as %s? Type yes: ' "$(label "$p")"
            IFS= read -r answer || exit 0
            [ "$answer" = yes ] || exit 0
            capture_profile "$p" ;;
        6) restore_backup ;;
        7) update_program; return ;;
        *) die 'Invalid selection.' ;;
    esac
    printf '\nPress Enter to finish: '
    IFS= read -r answer || true
}

nav_pick() {
    local result
    result=$("$NAV_HELPER" "$@") || die 'Controller menu stopped. No selection applied.'
    printf '%s' "$result"
}
menu() {
    [ "$NAV_AVAILABLE" = 1 ] || { keyboard_menu; return; }
    local choice p answer last=unknown name items=()
    [ ! -f "$STATE" ] || last=$(cat "$STATE")
    for p in n64 stadia xbox ps4; do
        name=$(label "$p")
        if [ -f "$PROFILES/$p/$GLOBAL" ]; then
            items+=("$p|Select $name")
        else
            items+=("missing|$name (not captured)")
        fi
    done
    choice=$(nav_pick '8BitDo Controller Selector v0.3.2' "$MODE | Last selected: $last" \
        "${items[@]}" 'capture|Capture current maps' 'undo|Undo last switch' 'update|Update selector' 'exit|Exit')
    case "$choice" in
        exit|cancel) return ;;
        update) update_program; return ;;
        missing) printf 'That controller has no saved profile. Map it first, then capture it.\n'; return ;;
        n64|stadia|xbox|ps4) apply_profile "$choice" ;;
        undo)
            answer=$(nav_pick 'Undo last switch?' "Restore the previous $MODE maps." 'cancel|Cancel' 'yes|Restore maps')
            [ "$answer" = yes ] || return 0
            restore_backup ;;
        capture)
            p=$(nav_pick 'Capture current maps' 'Which paired controller did you just map?' \
                'cancel|Cancel' 'n64|N64 (8BitDo mod)' 'stadia|Stadia' 'xbox|Xbox' 'ps4|PS4')
            [ "$p" != cancel ] || return 0
            answer=$(nav_pick "Save maps as $(label "$p")?" "Replaces this saved $MODE profile. Its previous maps will be backed up." \
                'cancel|Cancel' 'yes|Save current maps')
            [ "$answer" = yes ] || return 0
            capture_profile "$p" ;;
        *) die 'Invalid controller menu selection.' ;;
    esac
    "$NAV_HELPER" --wait 'Finished' 'Exit, then reconnect the pad to reload maps if you applied or restored a profile.' 'exit|Exit' >/dev/null || true
}

detect_mode() {
    [ -r "$INPUT_DEVICES" ] || return 0
    awk 'BEGIN { RS="" }
        /Handlers=.*event/ && !/Name=.*(Keyboard|Mouse|IMU)/ {
            if (/Vendor=057e Product=2009/) sw=1
            if (/Vendor=2dc8 Product=3106/) xi=1
        }
        END { if (sw && xi) print "ambiguous"; else if (xi) print "xinput"; else if (sw) print "switch" }' "$INPUT_DEVICES"
}
configure_mode() {
    local detected answer
    detected=$(detect_mode)
    case "$MODE" in auto|switch|xinput) ;; *) die 'Mode must be auto, switch or xinput.' ;; esac
    if [ "$MODE" = auto ]; then
        case "$detected" in
            switch|xinput) MODE=$detected ;;
            *)
                [ "${1:-menu}" = menu ] || die 'Receiver mode unavailable or ambiguous. Use --mode switch or --mode xinput.'
                if [ "$NAV_AVAILABLE" = 1 ]; then
                    answer=$(nav_pick 'Choose receiver USB mode' 'Chooses saved maps; does not change the adapter mode.' \
                        '1|XInput (2dc8:3106)' '2|Switch (057e:2009)' 'update|Update selector' '0|Exit')
                    [ "$answer" != cancel ] || exit 0
                else
                printf 'Receiver mode unavailable or ambiguous. Choose the adapter USB output mode:\n'
                printf 'This chooses saved maps; it does not change the adapter mode.\n'
                printf '1  XInput (2dc8:3106)\n2  Switch (057e:2009)\n7  Update selector\n0  Exit\nMode: '
                IFS= read -r answer || exit 0
                fi
                case "$answer" in 1) MODE=xinput ;; 2) MODE=switch ;; 7|update) update_program; exit 0 ;; 0) exit 0 ;; *) die 'Invalid mode selection.' ;; esac ;;
        esac
    elif [ -n "$detected" ] && [ "$detected" != ambiguous ] && [ "$detected" != "$MODE" ]; then
        die "Connected receiver uses $detected mode; requested $MODE. Change the adapter mode or choose $detected."
    fi
    case "$MODE" in
        switch) IDENTITY=057e_2009; PROFILES=$PROFILE_ROOT ;;
        xinput) IDENTITY=2dc8_3106; PROFILES="$PROFILE_ROOT/xinput" ;;
    esac
    GLOBAL="input_${IDENTITY}_v3.map"
    STATE="$PROFILES/last-selected"
    LAST_BACKUP="$PROFILES/last-backup"
}
if [ "${1:-}" = --mode ]; then
    [ "$#" -ge 2 ] || die 'Usage: --mode auto|switch|xinput [command]'
    MODE=$2
    shift 2
fi
# Updating requires no receiver, controller profile or chosen USB mode.
if [ "${1:-}" = update ]; then
    shift
    update_program "$@"
    exit $?
fi
configure_mode "${1:-menu}"

case "${1:-menu}" in
    menu) menu ;;
    status) status ;;
    apply) [ "$#" -eq 2 ] || die 'Usage: apply PROFILE'; apply_profile "$2" ;;
    capture)
        [ "$#" -eq 3 ] && [ "$3" = --yes ] || die 'Usage: capture PROFILE --yes (confirm the paired controller first)'
        capture_profile "$2" ;;
    restore) restore_backup ;;
    *) die 'Usage: [status | apply PROFILE | capture PROFILE --yes | restore | update [--no-pause]]' ;;
esac
