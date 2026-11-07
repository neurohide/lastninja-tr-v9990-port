#!/usr/bin/env python3
"""Build emu/lastninja.rom: ASCII16, bank 0 = machine.asm, banks 1-4 = C64 RAM image."""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
subprocess.run([sys.executable, os.path.join(HERE, 'gen6502.py')], check=True)
r = subprocess.run(['z80asm', '-o', 'machine.bin', '-Lmachine.lbl', 'machine.asm'], cwd=HERE,
                   capture_output=True, text=True)
if r.returncode:
    print(r.stdout, r.stderr); sys.exit(1)
code = open(os.path.join(HERE, 'machine.bin'), 'rb').read()
assert len(code) <= 0x4000, 'bank 0 overflow: %d' % len(code)
img = open(os.path.join(ROOT, 'dumps', 'game_run.mem'), 'rb').read()[:0x10000]
rom = code.ljust(0x4000, b'\xff') + img
rom = rom.ljust(0x20000, b'\xff')
open(os.path.join(HERE, 'lastninja.rom'), 'wb').write(rom)
print('lastninja.rom: bank0 %d bytes' % len(code))
