#!/bin/bash
# 8BitDo Controller Selector v0.1.0 for MiSTer
# Install in /media/fat/Scripts/. Existing profiles live in
# /media/fat/config/8bitdo-profiles/{n64,stadia,xbox,ps4}/.
# Keyboard: select a number, then Enter. Also works over SSH.
# After APPLY/RESTORE, exit the script, turn the pad off, wait for its
# input device to disappear, then reconnect. MiSTer caches loaded maps.
# Scope: only global/core *input_057e_2009_v3.map files. Other devices,
# advanced maps, keyboard maps, boot settings and services are untouched.
# CLI: status | apply PROFILE | capture PROFILE | restore
# capture requires explicit confirmation in the menu, or --yes on the CLI.
# CONFIG_ROOT override is for isolated tests or alternate config locations.

set -eu
umask 077
CONFIG_ROOT=${CONFIG_ROOT:-/media/fat/config}
INPUTS="$CONFIG_ROOT/inputs"
PROFILES="$CONFIG_ROOT/8bitdo-profiles"
GLOBAL=input_057e_2009_v3.map
STATE="$PROFILES/last-selected"
LAST_BACKUP="$PROFILES/last-backup"
LOCK="$PROFILES/.selector-lock"
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
    [ -f "$directory/$GLOBAL" ] || die "Missing main-menu map: $directory/$GLOBAL"
    for file in "$directory"/*input_057e_2009_v3.map; do
        [ -e "$file" ] || continue
        [ -f "$file" ] && [ ! -L "$file" ] || die "Not a regular map: $file"
        size=$(wc -c < "$file")
        [ "$size" -eq 128 ] || die "Expected a 128-byte v3 map: $file ($size bytes)"
        count=$((count + 1))
    done
    [ "$count" -gt 0 ] || die "No maps in $directory"
}
copy_maps() {
    local source=$1 destination=$2 file
    for file in "$source"/*input_057e_2009_v3.map; do
        [ -e "$file" ] || continue
        [ -f "$file" ] && [ ! -L "$file" ] || return 1
        cp -p "$file" "$destination/" || return 1
    done
}
remove_maps() {
    local directory=$1 file
    for file in "$directory"/*input_057e_2009_v3.map; do
        [ -e "$file" ] || continue
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
    mkdir -p "$PROFILES"
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
    for file in "$source"/*input_057e_2009_v3.map; do
        [ -e "$file" ] || continue
        cmp -s "$file" "$BACKUP/maps/${file##*/}" || die 'Backup verification failed.'
    done
    if [ -f "$STATE" ]; then cp "$STATE" "$BACKUP/last-selected"; fi
}
replace_maps() {
    local source=$1 destination=$2 file
    mkdir -p "$destination" "$WORK/staged"
    copy_maps "$source" "$WORK/staged" || die 'Staging failed; no maps changed.'
    for file in "$source"/*input_057e_2009_v3.map; do
        [ -e "$file" ] || continue
        cmp -s "$file" "$WORK/staged/${file##*/}" || die 'Staging verification failed.'
    done
    backup_maps "$destination"
    TARGET=$destination
    ROLLBACK="$BACKUP/maps"
    remove_maps "$destination" || die 'Could not clear previous receiver maps.'
    for file in "$WORK/staged"/*input_057e_2009_v3.map; do
        [ -e "$file" ] || continue
        mv -- "$file" "$destination/" || die 'Could not install map.'
    done
    for file in "$source"/*input_057e_2009_v3.map; do
        [ -e "$file" ] || continue
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
    valid_maps "$source/maps"
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
    printf '8BitDo Controller Selector v0.1.0\nReceiver identity: 057e:2009\n'
    printf 'Last selected by this script: '
    if [ -f "$STATE" ]; then cat "$STATE"; else printf 'unknown\n'; fi
    printf '(This is a record, not automatic controller detection.)\n\n'
    for p in n64 stadia xbox ps4; do
        printf '%s: ' "$(label "$p")"
        if [ -f "$PROFILES/$p/$GLOBAL" ]; then
            printf 'saved\n'
            for file in "$PROFILES/$p"/*input_057e_2009_v3.map; do
                [ -f "$file" ] && printf '  %s\n' "${file##*/}"
            done
        else
            printf 'not captured\n'
        fi
    done
}
menu() {
    local choice p answer
    status
    printf '\nUse the KEYBOARD: number then Enter.\n'
    printf '1  Select N64\n2  Select Stadia\n3  Select Xbox\n4  Select PS4 (requires saved profile)\n'
    printf '5  Capture current maps into a profile\n6  Undo last selector switch\n0  Exit\n\nChoice: '
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
        *) die 'Invalid selection.' ;;
    esac
    printf '\nPress Enter to finish: '
    IFS= read -r answer || true
}

case "${1:-menu}" in
    menu) menu ;;
    status) status ;;
    apply) [ "$#" -eq 2 ] || die 'Usage: apply PROFILE'; apply_profile "$2" ;;
    capture)
        [ "$#" -eq 3 ] && [ "$3" = --yes ] || die 'Usage: capture PROFILE --yes (confirm the paired controller first)'
        capture_profile "$2" ;;
    restore) restore_backup ;;
    *) die 'Usage: [status | apply PROFILE | capture PROFILE --yes | restore]' ;;
esac
