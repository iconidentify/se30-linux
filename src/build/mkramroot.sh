#!/bin/sh
# Runs inside the se30-build container as root: stage the RAM root that the
# kernel embeds as its initramfs (BusyBox + overlay, no modules).
set -e
R=/build/ramroot
rm -rf $R && mkdir -p $R
for d in bin sbin usr/bin usr/sbin etc proc sys dev run tmp root home mnt newroot var/log var/tmp lib; do
    mkdir -p $R/$d
done
chmod 1777 $R/tmp $R/var/tmp
mknod -m 600 $R/dev/console c 5 1
cp /build/debs/x/usr/bin/busybox $R/bin/busybox
while read -r p; do
    [ "$p" = bin/busybox ] && continue
    rel=$(echo "$p" | sed 's|[^/]*/|../|g; s|[^/]*$||')
    ln -sf "${rel}bin/busybox" "$R/$p"
done < /build/applets.txt
cp -a /build/overlay/. $R/
cp /build/initramfs/init $R/init && chmod 755 $R/init
chown -R 0:0 $R
du -sh $R
