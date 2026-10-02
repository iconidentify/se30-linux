#!/bin/sh
# Rebuild only the Linux partition of $1 from /build/finalroot.
set -e
IMG=$1
set -- $(python3 -c "
import struct
f=open('$IMG','rb'); f.seek(4*512); e=f.read(512); print(*struct.unpack('>II', e[8:16]))")
truncate -s $(($2 * 512)) /tmp/root.ext4
mkfs.ext4 -q -L se30root -E lazy_itable_init=0,lazy_journal_init=0,nodiscard -d /build/finalroot /tmp/root.ext4
e2fsck -fn /tmp/root.ext4 | tail -1
dd if=/tmp/root.ext4 of=$IMG bs=1M seek=$(($1 * 512)) oflag=seek_bytes conv=notrunc status=none
