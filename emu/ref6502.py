"""Tiny reference 6502 (no decimal mode) for differential tests."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'msx', 'tools'))
from parse6502 import OPS


class CPU:
    def __init__(s, mem, pc, a, x, y, p, sp=0xFF):
        s.m = mem; s.pc = pc; s.a = a; s.x = x; s.y = y; s.sp = sp
        s.N = p >> 7 & 1; s.V = p >> 6 & 1; s.D = p >> 3 & 1; s.I = p >> 2 & 1
        s.Z = p >> 1 & 1; s.C = p & 1; s.b = p & 0x10

    def P(s):
        return s.N << 7 | s.V << 6 | 0x20 | s.b | s.D << 3 | s.I << 2 | s.Z << 1 | s.C

    def rd(s, a): return s.m[a & 0xFFFF]
    def wr(s, a, v): s.m[a & 0xFFFF] = v & 0xFF
    def f8(s):
        v = s.rd(s.pc); s.pc = (s.pc + 1) & 0xFFFF; return v
    def f16(s):
        l = s.f8(); return l | s.f8() << 8
    def nz(s, v):
        s.N = v >> 7 & 1; s.Z = int(v & 0xFF == 0); return v & 0xFF
    def push(s, v): s.wr(0x100 + s.sp, v); s.sp = (s.sp - 1) & 0xFF
    def pop(s): s.sp = (s.sp + 1) & 0xFF; return s.rd(0x100 + s.sp)

    def ea(s, mode):
        if mode == 'zp': return s.f8()
        if mode == 'zpx': return (s.f8() + s.x) & 0xFF
        if mode == 'zpy': return (s.f8() + s.y) & 0xFF
        if mode == 'abs': return s.f16()
        if mode == 'abx': return (s.f16() + s.x) & 0xFFFF
        if mode == 'aby': return (s.f16() + s.y) & 0xFFFF
        if mode == 'izx':
            z = (s.f8() + s.x) & 0xFF; return s.rd(z) | s.rd((z + 1) & 0xFF) << 8
        if mode == 'izy':
            z = s.f8(); return ((s.rd(z) | s.rd((z + 1) & 0xFF) << 8) + s.y) & 0xFFFF

    def adc(s, v):
        r = s.a + v + s.C
        s.V = int(~(s.a ^ v) & (s.a ^ r) & 0x80 != 0); s.C = int(r > 255); s.a = s.nz(r)

    def cmp(s, r, v):
        s.C = int(r >= v); s.nz((r - v) & 0xFF)

    def step(s):
        op = s.f8(); mn, mode, _ = OPS[op]
        if mn in ('lda', 'ldx', 'ldy', 'and', 'ora', 'eor', 'adc', 'sbc', 'cmp', 'cpx', 'cpy', 'bit'):
            v = s.f8() if mode == 'imm' else s.rd(s.ea(mode))
            if mn == 'lda': s.a = s.nz(v)
            elif mn == 'ldx': s.x = s.nz(v)
            elif mn == 'ldy': s.y = s.nz(v)
            elif mn == 'and': s.a = s.nz(s.a & v)
            elif mn == 'ora': s.a = s.nz(s.a | v)
            elif mn == 'eor': s.a = s.nz(s.a ^ v)
            elif mn == 'adc': s.adc(v)
            elif mn == 'sbc': s.adc(v ^ 0xFF)
            elif mn == 'cmp': s.cmp(s.a, v)
            elif mn == 'cpx': s.cmp(s.x, v)
            elif mn == 'cpy': s.cmp(s.y, v)
            else: s.N = v >> 7 & 1; s.V = v >> 6 & 1; s.Z = int(s.a & v == 0)
        elif mn in ('sta', 'stx', 'sty'):
            s.wr(s.ea(mode), {'sta': s.a, 'stx': s.x, 'sty': s.y}[mn])
        elif mn in ('asl', 'lsr', 'rol', 'ror', 'inc', 'dec'):
            ad = None if mode == 'acc' else s.ea(mode)
            v = s.a if ad is None else s.rd(ad)
            if mn == 'asl': c = v >> 7; v = v << 1 & 255; s.C = c; s.nz(v)
            elif mn == 'lsr': s.C = v & 1; v >>= 1; s.nz(v)
            elif mn == 'rol': c = v >> 7; v = (v << 1 | s.C) & 255; s.C = c; s.nz(v)
            elif mn == 'ror': c = v & 1; v = v >> 1 | s.C << 7; s.C = c; s.nz(v)
            elif mn == 'inc': v = s.nz(v + 1)
            else: v = s.nz(v - 1)
            if ad is None: s.a = v
            else: s.wr(ad, v)
        elif mn == 'tax': s.x = s.nz(s.a)
        elif mn == 'tay': s.y = s.nz(s.a)
        elif mn == 'txa': s.a = s.nz(s.x)
        elif mn == 'tya': s.a = s.nz(s.y)
        elif mn == 'tsx': s.x = s.nz(s.sp)
        elif mn == 'txs': s.sp = s.x
        elif mn == 'inx': s.x = s.nz(s.x + 1)
        elif mn == 'iny': s.y = s.nz(s.y + 1)
        elif mn == 'dex': s.x = s.nz(s.x - 1)
        elif mn == 'dey': s.y = s.nz(s.y - 1)
        elif mn in ('clc', 'sec'): s.C = int(mn == 'sec')
        elif mn in ('cli', 'sei'): s.I = int(mn == 'sei')
        elif mn in ('cld', 'sed'): s.D = int(mn == 'sed')
        elif mn == 'clv': s.V = 0
        elif mn in ('bpl', 'bmi', 'bvc', 'bvs', 'bcc', 'bcs', 'bne', 'beq'):
            o = s.f8(); fl, w = {'bpl': (s.N, 0), 'bmi': (s.N, 1), 'bvc': (s.V, 0), 'bvs': (s.V, 1),
                                 'bcc': (s.C, 0), 'bcs': (s.C, 1), 'bne': (s.Z, 0), 'beq': (s.Z, 1)}[mn]
            if fl == w: s.pc = (s.pc + o - (256 if o > 127 else 0)) & 0xFFFF
        elif mn == 'pha': s.push(s.a)
        elif mn == 'php': s.push(s.P() | 0x30)
        elif mn == 'pla': s.a = s.nz(s.pop())
        elif mn == 'plp':
            p = s.pop() | 0x20; s.N = p >> 7 & 1; s.V = p >> 6 & 1; s.D = p >> 3 & 1
            s.I = p >> 2 & 1; s.Z = p >> 1 & 1; s.C = p & 1; s.b = p & 0x10
        elif mn == 'jmp':
            a = s.f16()
            if mode == 'ind': a = s.rd(a) | s.rd(a & 0xFF00 | (a + 1) & 0xFF) << 8
            s.pc = a
        elif mn == 'jsr':
            a = s.f16(); r = (s.pc - 1) & 0xFFFF; s.push(r >> 8); s.push(r & 255); s.pc = a
        elif mn == 'rts':
            l = s.pop(); h = s.pop(); s.pc = ((h << 8 | l) + 1) & 0xFFFF
        elif mn == 'rti':
            p = s.pop() | 0x20; s.N = p >> 7 & 1; s.V = p >> 6 & 1; s.D = p >> 3 & 1
            s.I = p >> 2 & 1; s.Z = p >> 1 & 1; s.C = p & 1; s.b = p & 0x10
            l = s.pop(); s.pc = l | s.pop() << 8
        elif mn == 'brk':
            s.pc = (s.pc + 1) & 0xFFFF; s.push(s.pc >> 8); s.push(s.pc & 255); s.push(s.P() | 0x30)
            s.I = 1; s.pc = s.rd(0xFFFE) | s.rd(0xFFFF) << 8
        elif mn == 'nop': pass
        else: raise ValueError(mn)
