#!/bin/sh
# Runs in se30-xbuild: cross-compile libXfont 1.5 (static) and TinyX Xfbdev
# for m68k, using the Debian m68k build root as the sysroot.
set -e
SYS=/build/debbuild
export PKG_CONFIG_SYSROOT_DIR=$SYS
export PKG_CONFIG_LIBDIR=$SYS/usr/lib/m68k-linux-gnu/pkgconfig:$SYS/usr/share/pkgconfig
export CC="m68k-linux-gnu-gcc --sysroot=$SYS"
export CFLAGS="-Os"
cd /build/tinyx-src/libXfont-1.5.4
if [ ! -e $SYS/usr/lib/m68k-linux-gnu/pkgconfig/xfont.pc ]; then
    ./configure --host=m68k-linux-gnu --prefix=/usr --libdir=/usr/lib/m68k-linux-gnu \
        --disable-shared --enable-static --disable-freetype --disable-devel-docs >/dev/null
    make -s -j$(nproc) >/dev/null
    make -s install DESTDIR=$SYS >/dev/null
fi
cd /build/tinyx-src/tinyx-master
[ -x configure ] || autoreconf -fi >/dev/null 2>&1
./configure --host=m68k-linux-gnu --prefix=/usr --disable-xvesa --enable-xfbdev \
    --disable-xdmcp --disable-xdm-auth-1 --disable-dpms --disable-screensaver --disable-xres \
    --with-fontdir=/usr/share/fonts/X11 \
    --with-default-font-path=/usr/share/fonts/X11/misc,built-ins >/dev/null
make -s -j$(nproc) 2>&1 | grep -E 'error|warning: implicit' | head -20
m68k-linux-gnu-strip -o /build/Xfbdev kdrive/fbdev/Xfbdev
ls -la /build/Xfbdev; file /build/Xfbdev
chown -R 1000:1000 /build/tinyx-src /build/Xfbdev
