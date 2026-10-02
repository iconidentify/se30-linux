#!/bin/sh
# Cursor tests with the hardware-style cursor TinyX
sh /build/hook-cursor.sh "$1"
install -m 755 /build/Xfbdev-hwcursor "$1/usr/local/bin/Xfbdev"
