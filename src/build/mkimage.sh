#!/bin/sh
# Runs inside the se30-build container as root.
set -e
cd /build
export ARCH=m68k CROSS_COMPILE=m68k-linux-gnu-
R=/build/rootfs
rm -rf $R out && mkdir -p $R out

# Root filesystem: BusyBox + config overlay + kernel modules
for d in bin sbin usr/bin usr/sbin etc proc sys dev run tmp root home mnt var/log var/tmp lib; do
    mkdir -p $R/$d
done
chmod 1777 $R/tmp $R/var/tmp
cp debs/x/usr/bin/busybox $R/bin/busybox
while read -r p; do
    [ "$p" = bin/busybox ] && continue
    rel=$(echo "$p" | sed 's|[^/]*/|../|g; s|[^/]*$||')
    ln -sf "${rel}bin/busybox" "$R/$p"
done < applets.txt
cp -a overlay/. $R/
chown -R 0:0 $R
make -C linux-7.2.8 -s INSTALL_MOD_PATH=$R INSTALL_MOD_STRIP=1 modules_install
rm -f $R/lib/modules/*/build

# Kernel for Penguin: stripped, gzipped ELF
m68k-linux-gnu-strip -o out/vmlinux linux-7.2.8/vmlinux
gzip -9nf out/vmlinux

# Disk image: Apple Partition Map + one ext4 partition labelled se30root
IMG=out/se30-linux.img
rm -f $IMG && truncate -s 512M $IMG
parted -s $IMG mklabel mac mkpart linux ext2 1MiB 100%
parted -s $IMG unit s print
set -- $(parted -sm $IMG unit s print | awk -F: '$5 ~ /ext2/ || $6 ~ /linux/ {gsub("s","",$2); gsub("s","",$4); print $2, $4}' | tail -1)
START=$1 SIZE=$2
echo "linux partition: start=$START size=$SIZE sectors"
truncate -s $((SIZE * 512)) out/root.ext4
mkfs.ext4 -q -L se30root -d $R out/root.ext4
dd if=out/root.ext4 of=$IMG bs=512 seek=$START conv=notrunc status=none
rm out/root.ext4
chown -R 1000:1000 out
ls -la out
