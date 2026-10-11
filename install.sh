#!/bin/bash
# Install the selector and included profiles without applying a mapping.
set -eu
SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEST=${MISTER_ROOT:-/media/fat}
SELECTOR=8BitDo_Controller_Selector.sh
HELPER=Scripts/.8bitdo-selector/controller-menu
UPDATER=8BitDo_Selector_Update.sh
if [ "${1:-}" = --program-only ] && [ "$#" -eq 1 ]; then
    export UPDATE_SOURCE_DIR="$SOURCE"
    exec bash "$SOURCE/Scripts/$SELECTOR" update --no-pause
fi
[ "$#" -eq 0 ] || { printf 'Usage: install.sh [--program-only]\n' >&2; exit 1; }
PROFILES="$DEST/config/8bitdo-profiles"
WORK=
LOCK=
cleanup() {
    [ -z "$WORK" ] || rm -rf -- "$WORK"
    [ -z "$LOCK" ] || rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$DEST" ] || die "MiSTer root does not exist: $DEST"
bash -n "$SOURCE/Scripts/$UPDATER" || die 'Updater syntax check failed.'
(cd "$SOURCE" && sha256sum -c update/program.sha256) || die 'Program checksum verification failed.'
bash -n "$SOURCE/Scripts/$SELECTOR" || die 'Selector syntax check failed.'
[ -f "$SOURCE/$HELPER" ] && [ ! -L "$SOURCE/$HELPER" ] || die 'Missing controller menu helper.'
(cd "$SOURCE" && sha256sum -c src/controller-menu.sha256) || die 'Controller menu checksum failed.'
[ ! -L "$DEST/Scripts/.8bitdo-selector" ] || die 'Helper directory must not be a symlink.'
if [ -e "$DEST/Scripts/.8bitdo-selector" ]; then
    [ -d "$DEST/Scripts/.8bitdo-selector" ] || die 'Helper path is not a directory.'
fi
if [ -e "$DEST/$HELPER" ]; then
    [ -f "$DEST/$HELPER" ] && [ ! -L "$DEST/$HELPER" ] || die 'Existing controller helper is not a regular file.'
fi

# Check every source and existing profile before changing files.
for p in n64 stadia xbox xinput/n64 xinput/stadia xinput/xbox xinput/ps4; do
    case "$p" in xinput/*) identity=2dc8_3106 ;; *) identity=057e_2009 ;; esac
    directory="$SOURCE/config/8bitdo-profiles/$p"
    for name in "input_${identity}_v3.map" "N64_input_${identity}_v3.map"; do
        file="$directory/$name"
        [ -f "$file" ] && [ ! -L "$file" ] || die "Missing regular map: $file"
        [ "$(wc -c < "$file")" -eq 128 ] || die "Invalid v3 map size: $file"
    done
    if [ -e "$PROFILES/$p" ]; then
        [ -d "$PROFILES/$p" ] && [ ! -L "$PROFILES/$p" ] || die "Invalid profile directory: $PROFILES/$p"
        for file in "$directory"/*input_${identity}_v3.map; do
            existing="$PROFILES/$p/${file##*/}"
            if [ -e "$existing" ]; then
                [ ! -L "$existing" ] && cmp -s "$file" "$existing" || die "Existing profile differs: $existing. Preserve or move it before installing."
            fi
        done
    fi
done

mkdir -p "$DEST/Scripts" "$PROFILES"
mkdir "$PROFILES/.selector-lock" 2>/dev/null || die 'Selector or another installer is running.'
LOCK="$PROFILES/.selector-lock"
WORK=$(mktemp -d "$PROFILES/.install-XXXXXX")
if [ -e "$DEST/Scripts/$UPDATER" ] || [ -L "$DEST/Scripts/$UPDATER" ]; then
    [ -f "$DEST/Scripts/$UPDATER" ] && [ ! -L "$DEST/Scripts/$UPDATER" ] || die 'Existing updater is not a regular file.'
    if ! cmp -s "$SOURCE/Scripts/$UPDATER" "$DEST/Scripts/$UPDATER"; then
        updater_backup=$(mktemp -d "$PROFILES/updater-backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")
        cp -p "$DEST/Scripts/$UPDATER" "$updater_backup/"
    fi
fi
cp "$SOURCE/Scripts/$SELECTOR" "$WORK/$SELECTOR"
chmod +x "$WORK/$SELECTOR"
cp "$SOURCE/$HELPER" "$WORK/controller-menu"
chmod +x "$WORK/controller-menu"
if [ -f "$DEST/$HELPER" ] && ! cmp -s "$SOURCE/$HELPER" "$DEST/$HELPER"; then
    helper_backup=$(mktemp -d "$PROFILES/helper-backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")
    cp -p "$DEST/$HELPER" "$helper_backup/"
    printf 'Previous controller helper backed up: %s\n' "$helper_backup"
fi
if [ -e "$DEST/Scripts/$SELECTOR" ]; then
    [ -f "$DEST/Scripts/$SELECTOR" ] && [ ! -L "$DEST/Scripts/$SELECTOR" ] || die 'Existing selector is not a regular file.'
    if ! cmp -s "$SOURCE/Scripts/$SELECTOR" "$DEST/Scripts/$SELECTOR"; then
        backup=$(mktemp -d "$PROFILES/installer-backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")
        cp -p "$DEST/Scripts/$SELECTOR" "$backup/"
        printf 'Previous selector backed up: %s\n' "$backup"
    fi
fi
for p in n64 stadia xbox xinput/n64 xinput/stadia xinput/xbox xinput/ps4; do
    case "$p" in xinput/*) identity=2dc8_3106 ;; *) identity=057e_2009 ;; esac
    mkdir -p "$PROFILES/$p"
    for file in "$SOURCE/config/8bitdo-profiles/$p"/*input_${identity}_v3.map; do
        existing="$PROFILES/$p/${file##*/}"
        if [ ! -e "$existing" ]; then
            cp -p "$file" "$WORK/${file##*/}"
            cmp -s "$file" "$WORK/${file##*/}" || die 'Map staging verification failed.'
            mv "$WORK/${file##*/}" "$existing"
        fi
    done
done
mkdir -p "$DEST/Scripts/.8bitdo-selector"
mv "$WORK/controller-menu" "$DEST/$HELPER"
mv "$WORK/$SELECTOR" "$DEST/Scripts/$SELECTOR"
rm -f -- "$DEST/Scripts/$UPDATER"
sync
printf 'Installed Switch profiles for N64, Stadia and Xbox, and XInput profiles for N64, Stadia, Xbox and PS4. Active maps are unchanged.\n'
printf 'Open Scripts > 8BitDo_Controller_Selector, or run:\n'
printf 'bash %s/Scripts/%s\n' "$DEST" "$SELECTOR"
