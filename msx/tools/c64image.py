"""Build the patched C64 memory image of the depacked game and trace its code.

The image comes from the byte comments in disasm/game.s.  Code is found by
recursive descent from the known entry points (game init, the raster IRQ
handlers and every entry of the indirect-jump tables), because the da65 info
file misses everything that is only reachable through jump tables.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from parse6502 import OPS, load_mem  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# Effects of the crack's start code at $0570 (no trainer), applied statically.
PATCHES = {}

GAME_START = 0xBD16
IRQ_HANDLERS = [0x5533, 0x554D]

# (table address, entry count): little-endian pointers to code.
JUMP_TABLES = []

# Routines that run with all RAM visible ($01=$30): $D000-$DFFF is RAM there.
RAM_MODE_RANGES = []


def load_image():
    mem = bytearray(open(os.path.join(ROOT, 'dumps', 'game_run.mem'), 'rb').read()[:0x10000])
    for a, v in PATCHES.items():
        mem[a] = v
    return mem


def table_targets(mem):
    out = []
    for base, n in JUMP_TABLES:
        for i in range(n):
            out.append(mem[base + 2 * i] | mem[base + 2 * i + 1] << 8)
    return out


def decode_at(mem, a):
    op = mem[a]
    if op not in OPS:
        return None
    mn, mode, n = OPS[op]
    if n == 2:
        v = mem[a + 1]
        if mode == 'rel':
            v = (a + 2 + (v - 256 if v & 0x80 else v)) & 0xFFFF
    elif n == 3:
        v = mem[a + 1] | mem[a + 2] << 8
    else:
        v = None
    return (op, mn, mode, v, n)


BAD = []


def trace(mem):
    """Return dict addr -> (op, mnem, mode, operand, len)."""
    ins = {}
    owner = {}
    todo = [GAME_START] + IRQ_HANDLERS + table_targets(mem)
    while todo:
        a = todo.pop()
        while a not in ins:
            d = decode_at(mem, a)
            if d is None:
                BAD.append(('opcode', a)); break
            op, mn, mode, v, n = d
            if any(b in owner and owner[b] != a for b in range(a, a + n)):
                BAD.append(('overlap', a))
            for b in range(a, a + n):
                owner[b] = a
            ins[a] = d
            if mode == 'rel' or (mn in ('jmp', 'jsr') and mode == 'abs'):
                todo.append(v)
            if mn in ('jmp', 'rts', 'rti', 'brk'):
                break
            a += n
    return ins


def ram_mode(addr):
    return any(lo <= addr <= hi for lo, hi in RAM_MODE_RANGES)


if __name__ == '__main__':
    mem = load_image()
    ins = trace(mem)
    nbytes = sum(d[4] for d in ins.values())
    print(len(BAD), 'bad paths', BAD[:12])
    print('%d instructions, %d bytes of code' % (len(ins), nbytes))
    out = sys.argv[1] if len(sys.argv) > 1 else None
    if out:
        json.dump({'%04X' % a: list(d) for a, d in sorted(ins.items())}, open(out, 'w'))
