#!/bin/sh
# Runs in se30-build (privileged). Builds the Debian root filesystem and
# writes it, plus the kernel, into /build/mame/card-run.img.
set -e
cd /build
R=/build/finalroot
rm -rf $R && cp -a debroot $R
cp -a debian-overlay/. $R/
(cd debian-overlay && find . -mindepth 1) | while read -r p; do chown -h 0:0 "$R/$p"; done
install -m 755 se30fb/se30fb $R/usr/local/bin/se30fb
cp -a modroot/lib/modules $R/usr/lib/
ln -sf /bin/busybox $R/usr/sbin/init
chroot $R passwd -d root >/dev/null
printf '127.0.0.1\tlocalhost\n127.0.1.1\tse30\n' > $R/etc/hosts
# X's request-name table is only for debugging and takes minutes to parse
mv $R/usr/lib/xorg/protocol.txt $R/usr/lib/xorg/protocol.txt.disabled
# Compile and cache the XKB keymap now so X doesn't run xkbcomp on the SE/30
mv $R/usr/bin/xkbcomp $R/usr/bin/xkbcomp.real
install -m 755 xkbcomp-cache.sh $R/usr/bin/xkbcomp
mount -t proc proc $R/proc; mount --bind /dev $R/dev
chroot $R sh -c 'Xvfb :9 -screen 0 512x342x8 -cc 0 -extension GLX -extension RENDER -fp /usr/share/fonts/X11/misc,built-ins -displayfd 3 3>/tmp/ready >/dev/null 2>&1 & p=$!; i=0; until [ -s /tmp/ready ] || [ $i -gt 180 ]; do sleep 1; i=$((i+1)); done; kill $p; wait $p; rm -f /tmp/ready /tmp/.X9-lock; rm -rf /tmp/.X11-unix'
umount $R/dev $R/proc
ls -la $R/var/cache/xkbcomp/
rm -rf $R/var/cache/apt/*.bin $R/var/lib/apt/lists/* $R/src
du -sh $R

IMG=/build/mame/card-run.img
set -- $(python3 -c "
import struct
f=open('$IMG','rb'); f.seek(4*512); e=f.read(512); print(*struct.unpack('>II', e[8:16]))")
START=$1 SIZE=$2
truncate -s $((SIZE * 512)) root.ext4
mkfs.ext4 -q -L se30root -E lazy_itable_init=0,lazy_journal_init=0,nodiscard -d $R root.ext4
e2fsck -fn root.ext4
dd if=root.ext4 of=$IMG bs=1M seek=$((START * 512)) oflag=seek_bytes conv=notrunc status=none
rm root.ext4

hmount $IMG 1 >/dev/null
hdel :Linux:vmlinux.gz
hcopy -r out/vmlinux.gz :Linux:vmlinux.gz
hattrib -t BINA -c '????' :Linux:vmlinux.gz
hdel ":Linux:Read Me"
hcopy -t mac/Read-Me.txt ":Linux:Read Me"
hattrib -t TEXT -c ttxt ":Linux:Read Me"
hls -l :Linux
humount
chown 1000:1000 $IMG
