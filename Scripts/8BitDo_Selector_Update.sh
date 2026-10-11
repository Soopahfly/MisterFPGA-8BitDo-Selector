#!/bin/bash
# Program-only updater. Saved profiles and active input maps are never installed.
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
for file in "${FILES[@]}"; do cmp -s "$WORK/staged/$file" "$DEST/$file" || changed=1; done
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
for file in "${FILES[@]}"; do mv "$WORK/staged/$file" "$DEST/$file"; done
sync
ROLLBACK=0
printf 'Updated selector, navigation helper and updater (%s).\n' "$revision"
printf 'Previous program files: %s\n' "$BACKUP"
printf 'Saved profiles, active maps and selector undo history are unchanged.\n'
