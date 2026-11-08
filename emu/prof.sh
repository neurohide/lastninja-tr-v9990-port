#!/bin/sh
# usage: emu/prof.sh <seconds>  -- sample the 6502 PC every 0.2 ms after boot, print top 6502 addresses
SECS=${1:-10}
HERE=$(cd "$(dirname "$0")" && pwd)
cat > /tmp/ln/prof.tcl <<TCL
set throttle off
set ::f [open /tmp/ln/prof.samples w]
proc s {} { puts \$::f "[format %04X [reg de]] [debug read memory 0xC00A] [format %04X [reg pc]] [expr {[debug read memory 0xC010] + 256*[debug read memory 0xC011]}] [format %.3f [machine_info time]]"; after time 0.0002 s }
after time ${PROF_FROM:-16} s
${PROF_TCL:-}
after time [expr {${PROF_FROM:-16} + $SECS}] { close \$::f; exit }
TCL
openmsx -machine Panasonic_FS-A1GT -ext gfx9000 -cart "$HERE/lastninja.rom" -romtype ASCII16 -diska "$HERE/lastninja.dsk" ${PROF_STATE:+-savestate $PROF_STATE} -script /tmp/ln/prof.tcl >/dev/null 2>&1
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
import os
rows = [l.split() for l in open('/tmp/ln/prof.samples')]
slow = os.environ.get('SLOW_FPS')
if slow:                                     # keep samples of 1 s windows below SLOW_FPS
    secs = {}
    for r in rows:
        s = int(float(r[4])); fr = int(r[3])
        lo, hi = secs.get(s, (fr, fr)); secs[s] = (min(lo, fr), max(hi, fr))
    keep = {s for s, (lo, hi) in secs.items() if hi - lo < int(slow)}
    print('slow seconds:', sorted(keep))
    rows = [r for r in rows if int(float(r[4])) in keep]
for r in rows:
    de, seg, pc = r[:3]; de = int(de, 16); seg = int(seg); pc = int(pc, 16); n += 1
    a = de if de < 0x4000 else ((seg - 4) << 14) | (de & 0x3FFF)
    c6[a & 0xFFF0] += 1
    i = bisect.bisect_right(addrs, pc) - 1
    cz[lab[addrs[i]] if i >= 0 else '?'] += 1
print('samples', n)
print('6502 (16-byte buckets):', ', '.join('%04X:%d%%' % (a, 100 * k // n) for a, k in c6.most_common(12)))
print('Z80:', ', '.join('%s:%d%%' % (a, 100 * k // n) for a, k in cz.most_common(30)))
import re
grp = collections.Counter()
def g(name):
    if re.match(r'(h_[0-9A-F]{2}|g\d+|core_dispatch|h_idle|h_mul|emu_bad)$', name): return 'core'
    if re.match(r'(rd_hi|wr_hi|rh_|wh_|rd_any|setpc|sp_|getpc|gp_|port_|io_|ir_|iw_|vic_irq|sid_gate|sg_|kt_|kernal|k_|f_|fg_|fo_|ff_|wr_ram|wrr)', name): return 'memory/io'
    if re.match(r'(sched_line|sc_|emu_done|irq_check|take_irq|ti_|hi_|lines_to|lte_|min_hl|tlat|div63|d63|tcnt)', name): return 'scheduler'
    if re.match(r'(frame_sync|fs_|sys_timer)', name): return 'throttle-wait'
    if re.match(r'(sound|sf_|sfb|psg|sid_|se_|env|div3|mul4|m44|sdp)', name): return 'sound'
    return 'video'
for a, k in cz.items(): grp[g(a)] += k
print('groups:', ', '.join('%s:%d%%' % (a, 100 * k // n) for a, k in grp.most_common()))
P
