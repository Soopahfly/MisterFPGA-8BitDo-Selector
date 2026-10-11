#!/bin/bash
# Build on a Linux host with an ARM hard-float musl cross toolchain.
set -eu
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
read -r -a headers <<< "${CPPFLAGS:-}"
${CC:-arm-linux-musleabihf-gcc} "${headers[@]}" -std=c11 -O2 -Wall -Wextra -Werror \
    -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard -static \
    src/controller-menu.c -o Scripts/.8bitdo-selector/controller-menu
${STRIP:-arm-linux-musleabihf-strip} Scripts/.8bitdo-selector/controller-menu
sha256sum Scripts/.8bitdo-selector/controller-menu > src/controller-menu.sha256
