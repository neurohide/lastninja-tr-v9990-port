#!/bin/sh
# usage: emu/run.sh <seconds> <outprefix> [extra tcl]  -- boots lastninja.rom (FS-A1GT + GFX9000)
SECS=${1:-20}; OUT=${2:-/tmp/ln/run}; EXTRA=${3:-}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$(dirname "$OUT")"
cat > "$OUT.tcl" <<TCL
set throttle off
set ::log [open "$OUT.txt" w]
proc w16 {a} { expr {[debug read memory \$a] + 256*[debug read memory [expr {\$a+1}]]} }
proc m6502 {a} { debug read "Main RAM" [expr {4*16384 + \$a}] }
proc tick {} {
  puts \$::log [format "t=%5.1f frames=%d line=%d irqs=%d pc6502=%04X port=%02X io=%d irr=%02X imr=%02X icr=%02X mask=%02X cra=%02X zp1B=%02X" [machine_info time] [w16 0xC010] [w16 0xC00E] [w16 0xC01E] [reg de] [debug read memory 0xC00C] [debug read memory 0xC00A] [debug read memory 0xC014] [debug read memory 0xC015] [debug read memory 0xC016] [debug read memory 0xC017] [debug read memory 0xC018] [m6502 0x1B]]
  flush \$::log
  after time 1 tick
}
after time 1 tick
$EXTRA
after time $SECS { screenshot $OUT.png; close \$::log; exit }
TCL
"${OPENMSX:-openmsx}" -machine Panasonic_FS-A1GT -ext gfx9000 -cart "$HERE/lastninja.rom" -romtype ASCII16 \
  -script "$OUT.tcl" > "$OUT.log" 2>&1
cat "$OUT.txt" | tail -${TAIL:-8}
