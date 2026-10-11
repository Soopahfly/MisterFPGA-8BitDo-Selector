# Controller menu build

The distributed helper targets MiSTer's Cortex-A9: ARMv7-A, VFPv3-D16,
hard-float EABI, statically linked. It needs no shared libraries on MiSTer.

`bash src/build.sh` builds the executable and its SHA-256 manifest with an
ARM musl cross compiler. The compiler needs Linux UAPI headers for evdev.
The native test suite uses the host's GCC and libc instead.

The v0.3.0 binary was built with GCC 13.3.0 (Ubuntu
13.3.0-6ubuntu2~24.04.1cross1), binutils 2.42, Linux 6.8 UAPI headers,
and an unmodified musl 1.2.4 source release:

- Source: https://musl.libc.org/releases/musl-1.2.4.tar.gz
- Mirror used: https://snapshot.ubuntu.com/ubuntu/20260828T000000Z/pool/universe/m/musl/musl_1.2.4.orig.tar.gz
- Source archive SHA-256: `7a35eae33d5372a7c0da1188de798726f68825513b7ae3ebe97aaaa52114f039`

For a wrapper toolchain, first build musl with the ARM GNU cross compiler:

```bash
./configure --prefix=/your/arm-musl --syslibdir=/your/arm-musl/lib \
  --target=arm-linux-gnueabihf CC=arm-linux-gnueabihf-gcc \
  CFLAGS='-Os -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard'
make -j4
make install
```

Then, from this repository:

```bash
CC=/your/arm-musl/bin/musl-gcc STRIP=arm-linux-gnueabihf-strip \
CPPFLAGS='-idirafter /usr/arm-linux-gnueabihf/include' bash src/build.sh
```

The helper explicitly uses the kernel's evdev record layout. On 32-bit ARM,
records are 16 bytes, regardless of libc's time_t width. This matters when
building with modern musl, which uses 64-bit time_t.

The helper source is MIT licensed. The linked musl code and GCC runtime
retain their own licenses; their copyright/license notices are in `licenses/`.
GCC's runtime exception permits linking its runtime with this application.
