#!/usr/bin/env python3
"""Reference for the level-load test: run the LOADTEST stub on ref6502 with a
Python KERNAL (SETLFS/SETNAM/LOAD/OPEN/CHRIN/...), write /tmp/ln/ref_load.bin."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from ref6502 import CPU
mem = bytearray(open(os.path.join(ROOT, 'dumps', 'state_ram.mem'), 'rb').read())
mem[0x340:0x349] = bytes([0x20, 0x00, 0x04, 0x20, 0x50, 0x04, 0x4C, 0x46, 0x03]); mem[0x4F2] = ord('1')
mem[1] = 0x35
mem[0xD011] = 0x80                     # raster >= 256 for the wait at $046F
c = CPU(mem, 0x340, 0x17, 0x0A, 0x00, 0x23, 0x10)
k = dict(sa=0, name=b'', data=b'', pos=0)
def rts(): l = c.pop(); h = c.pop(); c.pc = ((h << 8 | l) + 1) & 0xFFFF
def fopen():
    p = os.path.join(ROOT, 'disk', 'c64', k['name'].decode().lower()); k['data'] = open(p, 'rb').read(); k['pos'] = 0
def getc():
    d = k['data']
    if k['pos'] >= len(d): return None
    v = d[k['pos']]; k['pos'] += 1
    if k['pos'] == len(d): mem[0x90] |= 0x40
    return v
steps = 0
while c.pc != 0x346:
    steps += 1
    if c.pc >= 0xE000 and mem[1] & 2:
        a = c.pc
        if a == 0xFFBA: k['sa'] = c.y
        elif a == 0xFFBD: k['name'] = bytes(mem[(c.y << 8 | c.x) + i] for i in range(c.a))
        elif a == 0xFFC0: fopen()
        elif a == 0xFFCF: v = getc(); c.a = 0 if v is None else v
        elif a == 0xFFD5:
            fopen(); ad = getc() | getc() << 8
            if k['sa'] == 0: ad = c.y << 8 | c.x
            while True:
                v = getc()
                if v is None: break
                mem[ad] = v; ad += 1
            c.x, c.y = ad & 255, ad >> 8; mem[0x90] = 0x40
        elif a in (0xFF90, 0xFFC3, 0xFFC6, 0xFFCC, 0xFFE7, 0xF642): pass
        else: raise SystemExit('unknown KERNAL %04X' % a)
        c.C = 0; rts(); continue
    c.step()
    if steps > 50_000_000: raise SystemExit('timeout')
open('/tmp/ln/ref_load.bin', 'wb').write(mem)
print('ref load done in', steps, 'instructions')
