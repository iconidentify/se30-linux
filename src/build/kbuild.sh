#!/bin/sh
# Runs in se30-build: build kernel + ramroot initramfs, output to /build/out.
# $1 = output name suffix (vmlinux-$1.gz, modroot-$1)
set -e
N=${1:-base}
/build/mkramroot.sh >/dev/null
cd /build/linux-7.2.8
export ARCH=m68k CROSS_COMPILE=m68k-linux-gnu-
make -s olddefconfig
make -s -j$(nproc) vmlinux modules
m68k-linux-gnu-strip -o /build/out/vmlinux-$N vmlinux && gzip -9nf /build/out/vmlinux-$N
rm -rf /build/modroot-$N && make -s INSTALL_MOD_PATH=/build/modroot-$N INSTALL_MOD_STRIP=1 modules_install
rm -f /build/modroot-$N/lib/modules/*/build
chown -R 1000:1000 /build/linux-7.2.8 /build/out
ls -la /build/out/vmlinux-$N.gz
