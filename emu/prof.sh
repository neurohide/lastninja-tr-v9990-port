#!/bin/sh
# usage: emu/prof.sh <seconds>  -- sample the 6502 PC every 0.2 ms after boot, print top 6502 addresses
SECS=${1:-10}
HERE=$(cd "$(dirname "$0")" && pwd)
cat > /tmp/ln/prof.tcl <<TCL
set throttle off
set ::f [open /tmp/ln/prof.samples w]
proc s {} { puts \$::f "[format %04X [reg de]] [debug read memory 0xC00A] [format %04X [reg pc]]"; after time 0.0002 s }
after time 15 s
after time [expr {15 + $SECS}] { close \$::f; exit }
TCL
openmsx -machine Panasonic_FS-A1GT -ext gfx9000 -cart "$HERE/lastninja.rom" -romtype ASCII16 -script /tmp/ln/prof.tcl >/dev/null 2>&1
python3 - "$HERE/machine.lbl" <<'P'
import sys, collections
lab = {}
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) >= 3 and p[1] == 'equ':
        lab[int(p[2].lstrip('$'), 16)] = p[0].rstrip(':')
addrs = sorted(lab)
import bisect
c6, cz = collections.Counter(), collections.Counter()
n = 0
for l in open('/tmp/ln/prof.samples'):
    de, seg, pc = l.split(); de = int(de, 16); seg = int(seg); pc = int(pc, 16); n += 1
    a = de if de < 0x4000 else ((seg - 4) << 14) | (de & 0x3FFF)
    c6[a & 0xFFF0] += 1
    i = bisect.bisect_right(addrs, pc) - 1
    cz[lab[addrs[i]] if i >= 0 else '?'] += 1
print('samples', n)
print('6502 (16-byte buckets):', ', '.join('%04X:%d%%' % (a, 100 * k // n) for a, k in c6.most_common(12)))
print('Z80:', ', '.join('%s:%d%%' % (a, 100 * k // n) for a, k in cz.most_common(14)))
P
