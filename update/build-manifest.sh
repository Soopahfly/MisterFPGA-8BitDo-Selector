#!/bin/bash
set -eu
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
sha256sum Scripts/8BitDo_Controller_Selector.sh Scripts/8BitDo_Selector_Update.sh \
    Scripts/.8bitdo-selector/controller-menu > update/program.sha256
