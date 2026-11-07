#!/bin/sh
# usage: emu/bench.sh [label]  -- AUTOWALK build, no throttle: host seconds per 100 emulated frames
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE" && AUTOWALK=1 THROTTLE=0 python3 embuild.py >/dev/null || exit 1
cat > /tmp/ln/bench.tcl <<'TCL'
set throttle off
set ::f [open /tmp/ln/bench.txt w]
set ::next 0
proc chk {} {
  set fr [expr {[debug read memory 0xC010] + 256*[debug read memory 0xC011]}]
  if {$fr >= $::next && $::next <= 700} { puts $::f "$::next [format %.2f [machine_info time]]"; flush $::f; incr ::next 100 }
  if {$::next > 700} { close $::f; exit }
  after time 0.05 chk
}
after time 12 chk
after time 200 { close $::f; exit }
TCL
openmsx -machine Panasonic_FS-A1GT -ext gfx9000 -cart lastninja.rom -romtype ASCII16 -diska lastninja.dsk -script /tmp/ln/bench.tcl >/dev/null 2>&1
python3 - "$1" <<'P'
import sys
r=[l.split() for l in open('/tmp/ln/bench.txt')]
t={int(a):float(b) for a,b in r}
print(sys.argv[1] if len(sys.argv)>1 else '', ' '.join('%d-%d:%.2fs' % (k-100,k,t[k]-t[k-100]) for k in sorted(t) if k-100 in t))
P
