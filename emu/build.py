#!/usr/bin/env python3
"""Build emu/lastninja.rom: ASCII16, bank 0 = machine.asm, banks 1-4 = C64 RAM image."""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
import json
subprocess.run([sys.executable, os.path.join(HERE, 'gen6502.py')], check=True)
st = json.load(open(os.path.join(ROOT, 'dumps', 'state.json')))
h = lambda k: int(st[k], 16)
open(os.path.join(HERE, 'state.inc'), 'w').write(''.join('%s:\tequ $%04X\n' % kv for kv in [
    ('START_PC', h('pc')), ('START_PORT', h('port')), ('ST_A', h('a')), ('ST_X', h('x')), ('ST_Y', h('y')),
    ('ST_S', h('s')), ('ST_P', h('p')), ('ST_CMP', st['raster_cmp']), ('ST_IMR', h('imr')),
    ('ST_MASK', h('cia1_mask')), ('ST_CRA', h('cia1_cra')), ('ST_TLAT', h('cia1_latch')), ('ST_TCNT', h('cia1_count')), ('RENDER_TEST', int(os.environ.get('RENDER_TEST', '0')))]))
r = subprocess.run(['z80asm', '-o', 'machine.bin', '-Lmachine.lbl', 'machine.asm'], cwd=HERE,
                   capture_output=True, text=True)
if r.returncode:
    print(r.stdout, r.stderr); sys.exit(1)
code = open(os.path.join(HERE, 'machine.bin'), 'rb').read()
assert len(code) <= 0x4000, 'bank 0 overflow: %d' % len(code)
img = open(os.path.join(ROOT, 'dumps', 'state_ram.mem'), 'rb').read()[:0x10000]
io = open(os.path.join(ROOT, 'dumps', 'state_io.mem'), 'rb').read()
rom = code.ljust(0x4000, b'\xff') + img + io
rom = rom.ljust(0x20000, b'\xff')
open(os.path.join(HERE, 'lastninja.rom'), 'wb').write(rom)
print('lastninja.rom: bank0 %d bytes' % len(code))
