#!/usr/bin/env python3
# Shrink the card's HFS partition in place and add a Linux partition after it.
# Only the HFS size fields (MDB + alternate MDB) and the partition map change.
import struct, sys
img, HFS_SECTORS = sys.argv[1], int(sys.argv[2])
f = open(img, 'r+b')

def rd(sector, n=1):
    f.seek(sector * 512); return bytearray(f.read(512 * n))
def wr(sector, data):
    f.seek(sector * 512); f.write(data)

ddm = rd(0)
assert ddm[:2] == b'ER'
disk_blocks = struct.unpack('>I', ddm[4:8])[0]
entries = [rd(i) for i in range(1, struct.unpack('>I', rd(1)[4:8])[0] + 1)]
hfs_i = next(i for i, e in enumerate(entries) if e[48:80].rstrip(b'\0') == b'Apple_HFS')
hfs = entries[hfs_i]
P, old_sectors = struct.unpack('>II', hfs[8:16])
assert P + old_sectors == disk_blocks, "HFS partition is not last"

# HFS volume: shrink the allocation block count
mdb = rd(P + 2)
assert mdb[:2] == b'BD'
nmAlBlks, alBlkSiz = struct.unpack('>HI', mdb[18:24])
alBlSt, = struct.unpack('>H', mdb[28:30])
freeBks, = struct.unpack('>H', mdb[34:36])
vbmSt, = struct.unpack('>H', mdb[14:16])
new_blks = (HFS_SECTORS * 512 - alBlSt * 512 - 1024) // alBlkSiz
bm = rd(P + vbmSt, (nmAlBlks + 4095) // 4096)
highest = max(i for i in range(nmAlBlks) if bm[i // 8] & (0x80 >> (i % 8)))
assert highest < new_blks, f"allocated block {highest} beyond new end {new_blks}"
new_free = freeBks - (nmAlBlks - new_blks)
struct.pack_into('>H', mdb, 18, new_blks)
struct.pack_into('>H', mdb, 34, new_free)
wr(P + 2, mdb)
wr(P + HFS_SECTORS - 2, mdb)          # alternate MDB, second-to-last sector
print(f"HFS: {nmAlBlks} -> {new_blks} blocks of {alBlkSiz}, free {freeBks} -> {new_free}, highest used {highest}")

# Partition map: shrink HFS entry, append Linux entry
struct.pack_into('>II', hfs, 8, P, HFS_SECTORS)
struct.pack_into('>I', hfs, 84, HFS_SECTORS)  # pmDataCnt
L = P + HFS_SECTORS
lin = bytearray(512)
lin[0:2] = b'PM'
struct.pack_into('>II', lin, 8, L, disk_blocks - L)
lin[16:16 + 10] = b'Linux root'
lin[48:48 + 15] = b'Apple_UNIX_SVR2'
struct.pack_into('>II', lin, 80, 0, disk_blocks - L)  # pmLgDataStart, pmDataCnt
struct.pack_into('>I', lin, 88, 0x33)                 # valid | allocated | readable | writable
entries.append(lin)
for i, e in enumerate(entries):
    struct.pack_into('>I', e, 4, len(entries))
    wr(1 + i, e)
f.close()
print(f"Linux partition: start={L} sectors={disk_blocks - L}")
