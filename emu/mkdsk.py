#!/usr/bin/env python3
"""Write emu/lastninja.dsk: 720K FAT12 MSX-DOS disk with the C64 level files
from disk/c64/ (names upper-cased, contents unchanged, PRG load address kept)."""
import os, struct, time
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), 'disk', 'c64')
SEC, TOTAL, SPC, RES, NFAT, ROOT, SPF = 512, 1440, 2, 1, 2, 112, 3
img = bytearray(SEC * TOTAL)
boot = bytearray(SEC)
boot[0:3] = b'\xEB\xFE\x90'
boot[3:11] = b'LNINJA  '
struct.pack_into('<HBHBHHBHHH', boot, 11, SEC, SPC, RES, NFAT, ROOT, TOTAL, 0xF9, SPF, 9, 2)
boot[0x1E] = 0xC9                      # boot code: ret
img[0:SEC] = boot
fat = bytearray(SPF * SEC)
fat[0:3] = b'\xF9\xFF\xFF'
root_sec = RES + NFAT * SPF
data_sec = root_sec + ROOT * 32 // SEC
def setfat(n, v):
    o = n * 3 // 2
    if n & 1:
        fat[o] = fat[o] & 0x0F | (v << 4) & 0xF0; fat[o + 1] = v >> 4 & 0xFF
    else:
        fat[o] = v & 0xFF; fat[o + 1] = fat[o + 1] & 0xF0 | v >> 8 & 0x0F
clus = 2
t = time.localtime()
dtime = t.tm_hour << 11 | t.tm_min << 5 | t.tm_sec // 2
ddate = (t.tm_year - 1980) << 9 | t.tm_mon << 5 | t.tm_mday
names = sorted(os.listdir(SRC))
assert len(names) <= ROOT
for i, name in enumerate(names):
    data = open(os.path.join(SRC, name), 'rb').read()
    n = (len(data) + SPC * SEC - 1) // (SPC * SEC)
    first = clus if data else 0
    for k in range(n):
        setfat(clus + k, clus + k + 1 if k < n - 1 else 0xFFF)
        o = (data_sec + (clus + k - 2) * SPC) * SEC
        chunk = data[k * SPC * SEC:(k + 1) * SPC * SEC]
        img[o:o + len(chunk)] = chunk
    clus += n
    base, _, ext = name.upper().partition('.')
    ent = base.ljust(8).encode()[:8] + ext.ljust(3).encode()[:3]
    ent += bytes([0x20]) + bytes(10) + struct.pack('<HHHI', dtime, ddate, first, len(data))
    img[root_sec * SEC + i * 32:root_sec * SEC + i * 32 + 32] = ent
assert data_sec + (clus - 2) * SPC <= TOTAL, 'disk full'
for f in range(NFAT):
    img[(RES + f * SPF) * SEC:(RES + (f + 1) * SPF) * SEC] = fat
open(os.path.join(HERE, 'lastninja.dsk'), 'wb').write(img)
print('lastninja.dsk: %d files, %d clusters used' % (len(names), clus - 2))
