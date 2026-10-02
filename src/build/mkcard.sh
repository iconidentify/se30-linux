#!/bin/sh
# Runs inside se30-build as root: build card.img from the card backup.
set -e
cd /build
HFS_SECTORS=524288                       # 256 MiB for System 7.1
cp mame/card-orig.img card.img
python3 relayout.py card.img $HFS_SECTORS
set -- $(python3 -c "
import struct
f=open('card.img','rb'); f.seek(4*512); e=f.read(512); print(*struct.unpack('>II', e[8:16]))")
START=$1 SIZE=$2
truncate -s $((SIZE * 512)) root.ext4
mkfs.ext4 -q -L se30root -E lazy_itable_init=0,lazy_journal_init=0,nodiscard -d rootfs root.ext4
dd if=root.ext4 of=card.img bs=1M seek=$((START * 512)) oflag=seek_bytes conv=notrunc status=none
rm root.ext4
hmount card.img 1 >/dev/null
hmkdir :Linux
hcopy -m mac/Penguin-19.bin ":Linux:Penguin 19"
hcopy -r out/vmlinux.gz :Linux:vmlinux.gz
hattrib -t BINA -c '????' :Linux:vmlinux.gz
hcopy -t mac/Read-Me.txt ":Linux:Read Me"
hattrib -t TEXT -c ttxt ":Linux:Read Me"
hcopy -m mac/m32bin/MODE32_Installer.bin ":Linux:MODE32 Installer"
hcopy -m mac/m32bin/MODE32-Important_Instructions.bin ":Linux:MODE32 Instructions"
hls -l :Linux
hvol
humount
chown 1000:1000 card.img
