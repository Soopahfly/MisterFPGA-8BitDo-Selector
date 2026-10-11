#!/bin/bash
# Compatibility bridge for v0.3.1. New installations do not install this entry.
# The main selector contains the complete updater and removes this legacy file.
set -eu
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$SCRIPT_DIR/8BitDo_Controller_Selector.sh" update "$@"
