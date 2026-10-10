#!/bin/bash
# Install the selector and included profiles without applying a mapping.
set -eu
SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEST=${MISTER_ROOT:-/media/fat}
SELECTOR=8BitDo_Controller_Selector.sh
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
bash -n "$SOURCE/Scripts/$SELECTOR" || die 'Selector syntax check failed.'

# Check every source and existing profile before changing files.
for p in n64 stadia xbox xinput/n64 xinput/stadia xinput/xbox; do
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
cp "$SOURCE/Scripts/$SELECTOR" "$WORK/$SELECTOR"
chmod +x "$WORK/$SELECTOR"
if [ -e "$DEST/Scripts/$SELECTOR" ]; then
    [ -f "$DEST/Scripts/$SELECTOR" ] && [ ! -L "$DEST/Scripts/$SELECTOR" ] || die 'Existing selector is not a regular file.'
    if ! cmp -s "$SOURCE/Scripts/$SELECTOR" "$DEST/Scripts/$SELECTOR"; then
        backup=$(mktemp -d "$PROFILES/installer-backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")
        cp -p "$DEST/Scripts/$SELECTOR" "$backup/"
        printf 'Previous selector backed up: %s\n' "$backup"
    fi
fi
for p in n64 stadia xbox xinput/n64 xinput/stadia xinput/xbox; do
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
mv "$WORK/$SELECTOR" "$DEST/Scripts/$SELECTOR"
sync
printf 'Installed Switch and XInput profiles for N64, Stadia and Xbox. Active maps are unchanged.\n'
printf 'Open Scripts > 8BitDo_Controller_Selector, or run:\n'
printf 'bash %s/Scripts/%s\n' "$DEST" "$SELECTOR"
