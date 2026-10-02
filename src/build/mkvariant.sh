#!/bin/sh
# Runs in se30-build (privileged): build a test image.
# usage: mkvariant.sh <kernel.gz> <modroot> <base.img> <out.img> [rootfs-hook.sh]
# The hook runs as "sh hook <rootdir>" to apply a variant's changes.
set -e
cd /build
K=$1 M=$2 BASE=$3 OUT=$4 HOOK=$5
R=/build/vroot
rm -rf $R && cp -a debroot $R
cp -a debian-overlay/. $R/
(cd debian-overlay && find . -mindepth 1) | while read -r p; do chown -h 0:0 "$R/$p"; done
install -m 755 se30fb/se30fb $R/usr/local/bin/se30fb
cp -a $M/lib/modules $R/usr/lib/
ln -sf /bin/busybox $R/usr/sbin/init
chroot $R passwd -d root >/dev/null
printf '127.0.0.1\tlocalhost\n127.0.1.1\tse30\n' > $R/etc/hosts
mv $R/usr/lib/xorg/protocol.txt $R/usr/lib/xorg/protocol.txt.disabled
mv $R/usr/bin/xkbcomp $R/usr/bin/xkbcomp.real
install -m 755 xkbcomp-cache.sh $R/usr/bin/xkbcomp
[ -n "$HOOK" ] && sh "$HOOK" $R
mount -t proc proc $R/proc; mount --bind /dev $R/dev
chroot $R sh -c 'Xvfb :9 -screen 0 512x342x8 -cc 0 -extension GLX -extension RENDER -fp /usr/share/fonts/X11/misc,built-ins -displayfd 3 3>/tmp/ready >/dev/null 2>&1 & p=$!; i=0; until [ -s /tmp/ready ] || [ $i -gt 180 ]; do sleep 1; i=$((i+1)); done; kill $p; wait $p; rm -f /tmp/ready /tmp/.X9-lock; rm -rf /tmp/.X11-unix'
umount $R/dev $R/proc
rm -rf $R/var/cache/apt/*.bin $R/var/lib/apt/lists/* $R/src

cp --sparse=always $BASE $OUT
set -- $(python3 -c "
import struct
f=open('$OUT','rb'); f.seek(4*512); e=f.read(512); print(*struct.unpack('>II', e[8:16]))")
truncate -s $(($2 * 512)) /tmp/root.ext4
mkfs.ext4 -q -L se30root -E lazy_itable_init=0,lazy_journal_init=0,nodiscard -d $R /tmp/root.ext4
e2fsck -fn /tmp/root.ext4 >/dev/null
dd if=/tmp/root.ext4 of=$OUT bs=1M seek=$(($1 * 512)) oflag=seek_bytes conv=notrunc status=none
rm /tmp/root.ext4
hmount $OUT 1 >/dev/null
hdel :Linux:vmlinux.gz
hcopy -r $K :Linux:vmlinux.gz
hattrib -t BINA -c '????' :Linux:vmlinux.gz
humount
chown 1000:1000 $OUT
echo "built $OUT"
