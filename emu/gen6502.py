#!/usr/bin/env python3
"""Generate emu/core.asm: a fast 6502 interpreter for the Z80/R800.

Memory layout (set up by machine.asm):
  Z80 page 0 = 6502 $0000-$3FFF (direct: zero page, stack, low RAM)
  Z80 page 1 = this core (RAM copy)
  Z80 page 2 = window for 6502 $4000-$FFFF (segment SEG0+1..SEG0+3)
  Z80 page 3 = system RAM (RV_* variables, Z80 stack)

Registers: DE = Z80 pointer to the next 6502 code byte, B = X, C = Y.
6502 A, S and lazy flags live in RAM:
  N source in IXh (bit 7 = N)          Z source in IXl (0 = Z set)   6502 A in IYl
  RV_C  $FF/$00 carry                 RV_V  non-zero when V is set
  RV_P  I and D bits (2, 3)
RV_S is followed by a constant $01 byte, so `ld hl,(RV_S)` points at the stack.

The slice counter RV_CNT is decremented on branches, jumps, calls and returns
(every instruction when COUNT_ALL=1, for tests); at 0 the core jumps to
emu_done with DE/B/C live.  Decimal mode is not emulated.
usage: gen6502.py [COUNT_ALL]
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'msx', 'tools'))
from parse6502 import OPS  # noqa: E402

COUNT_ALL = len(sys.argv) > 1 and sys.argv[1] == '1'
out = []
n = [0]


# 6502 A lives in IYl, the N and Z sources in IXh/IXl (raw bytes: z80asm
# mis-encodes some IX/IY-half instructions).
RAW = {'ld (RV_A),a': 'db $FD,$6F', 'ld a,(RV_A)': 'db $FD,$7D', 'ld (RV_N),a': 'db $DD,$67', 'ld a,(RV_N)': 'db $DD,$7C', 'ld (RV_Z),a': 'db $DD,$6F', 'ld a,(RV_Z)': 'db $DD,$7D'}


def e(*lines):
    for l in lines:
        l = RAW.get(l, l)
        out.append(l if l.endswith(':') else '\t' + l)


def lab():
    n[0] += 1
    return 'g%d' % n[0]


def dispatch():
    if COUNT_ALL:
        e('ld hl,RV_CNT', 'dec (hl)', 'jp z,emu_done')
    e('ld a,(de)', 'inc de', 'ld l,a', 'ld h,optab_lo/256', 'ld a,(hl)', 'inc h', 'ld h,(hl)',
      'ld l,a', 'jp (hl)')


def count():
    """Slice counter on control flow (no-op in COUNT_ALL mode, counted in dispatch)."""
    if not COUNT_ALL:
        e('ld hl,RV_CNT', 'dec (hl)', 'jp z,emu_done')


def fetch_ea(mode):
    """HL = effective address (not for imm/acc/zp-direct shortcuts)."""
    if mode == 'zp':
        e('ld a,(de)', 'inc de', 'ld l,a', 'ld h,0')
    elif mode == 'zpx':
        e('ld a,(de)', 'inc de', 'add a,b', 'ld l,a', 'ld h,0')
    elif mode == 'zpy':
        e('ld a,(de)', 'inc de', 'add a,c', 'ld l,a', 'ld h,0')
    elif mode == 'abs':
        e('ld a,(de)', 'inc de', 'ld l,a', 'ld a,(de)', 'inc de', 'ld h,a')
    elif mode in ('abx', 'aby'):
        r = 'b' if mode == 'abx' else 'c'
        e('ld a,(de)', 'inc de', 'add a,%s' % r, 'ld l,a', 'ld a,(de)', 'inc de', 'adc a,0', 'ld h,a')
    elif mode == 'izx':
        e('ld a,(de)', 'inc de', 'add a,b', 'ld l,a', 'ld h,0', 'ld a,(hl)', 'inc l', 'ld h,(hl)',
          'ld l,a')
    elif mode == 'izy':
        e('ld a,(de)', 'inc de', 'ld l,a', 'ld h,0', 'ld a,(hl)', 'inc l', 'ld h,(hl)', 'add a,c',
          'ld l,a', 'jr nc,$+3', 'inc h')
    else:
        raise ValueError(mode)


def is_zp(mode):
    return mode in ('zp', 'zpx', 'zpy')


def read(mode):
    """A = operand value."""
    if mode == 'imm':
        e('ld a,(de)', 'inc de')
        return
    fetch_ea(mode)
    if is_zp(mode):
        e('ld a,(hl)')
    else:
        a, b, c = lab(), lab(), lab()
        # page 0: direct; same 16K segment as the code (RV_CODEHI): inline window read
        e('ld a,h', 'cp $40', 'jr nc,%s' % a, 'ld a,(hl)', 'jr %s' % b,
          '%s:' % a, 'ld a,(RV_CODEHI)', 'xor h', 'and $C0', 'jr nz,%s' % c, 'set 7,h', 'res 6,h',
          'ld a,(hl)', 'jr %s' % b, '%s:' % c, 'call rd_hi', '%s:' % b)


def write(mode, val):
    """Store `val` (an 8-bit source for `ld a,...`) at the EA in HL."""
    a, b = lab(), lab()
    if is_zp(mode):
        if TRAPS_ZP:
            e('ld a,l', 'cp 1', 'ld a,%s' % val, 'jr z,%s' % a, 'ld (hl),a', 'jr %s' % b,
              '%s:' % a, 'call port_wr', 'ld (hl),a', '%s:' % b)
        else:
            e('ld a,%s' % val, 'ld (hl),a')
    else:
        c = lab()
        e('ld a,h', 'cp $40', 'ld a,%s' % val, 'jr nc,%s' % a, 'ld (hl),a', 'jr %s' % b,
          '%s:' % a, 'ld a,(RV_CODEHI)', 'xor h', 'and $C0', 'ld a,%s' % val, 'jr nz,%s' % c,
          'set 7,h', 'res 6,h', 'ld (hl),a', 'jr %s' % b, '%s:' % c, 'call wr_hi', '%s:' % b)


TRAPS_ZP = False   # $0001 is read where the memory map matters (machine.asm port_io/port_kern)


def setnz():
    e('ld (RV_N),a', 'ld (RV_Z),a')


def carry_out():
    """RV_C from the Z80 carry (A is clobbered)."""
    e('sbc a,a', 'ld (RV_C),a')


def rmw_op(mn):
    """A = value -> A = result, flags stored."""
    if mn == 'asl':
        e('add a,a', 'ld l,a', 'sbc a,a', 'ld (RV_C),a', 'ld a,l')
    elif mn == 'lsr':
        e('srl a', 'ld l,a', 'sbc a,a', 'ld (RV_C),a', 'ld a,l')
    elif mn in ('rol', 'ror'):
        e('ld l,a', 'ld a,(RV_C)', 'rra', 'ld a,l', 'rla' if mn == 'rol' else 'rra', 'ld l,a',
          'sbc a,a', 'ld (RV_C),a', 'ld a,l')
    elif mn == 'inc':
        e('inc a')
    elif mn == 'dec':
        e('dec a')
    setnz()


BR = {'bpl': ('RV_N', 'rla', 'c'), 'bmi': ('RV_N', 'rla', 'nc'),
      'bvc': ('RV_V', 'or a', 'nz'), 'bvs': ('RV_V', 'or a', 'z'),
      'bcc': ('RV_C', 'or a', 'nz'), 'bcs': ('RV_C', 'or a', 'z'),
      'bne': ('RV_Z', 'or a', 'z'), 'beq': ('RV_Z', 'or a', 'nz')}  # (var, test, skip-if)


def handler(op, mn, mode):
    name = 'h_%02X' % op
    e('%s:' % name)
    if mn in ('lda', 'ldx', 'ldy'):
        read(mode)
        e({'lda': 'ld (RV_A),a', 'ldx': 'ld b,a', 'ldy': 'ld c,a'}[mn])
        setnz()
    elif mn in ('sta', 'stx', 'sty'):
        fetch_ea(mode)
        write(mode, {'sta': '(RV_A)', 'stx': 'b', 'sty': 'c'}[mn])
    elif mn in ('and', 'ora', 'eor'):
        read(mode)
        e('ld l,a', 'ld a,(RV_A)', '%s l' % {'and': 'and', 'ora': 'or', 'eor': 'xor'}[mn],
          'ld (RV_A),a')
        setnz()
    elif mn in ('adc', 'sbc'):
        read(mode)
        e('ld l,a', 'ld a,(RV_C)')
        if mn == 'sbc':
            e('cpl')
        e('rra', 'ld a,(RV_A)', '%s a,l' % mn, 'ld (RV_A),a')
        setnz()
        e('push af', 'pop hl', 'ld a,l', 'and 4', 'ld (RV_V),a', 'ld a,l')
        if mn == 'sbc':
            e('cpl')
        e('rra')
        carry_out()
    elif mn in ('cmp', 'cpx', 'cpy'):
        read(mode)
        e('ld l,a', {'cmp': 'ld a,(RV_A)', 'cpx': 'ld a,b', 'cpy': 'ld a,c'}[mn], 'sub l')
        setnz()
        e('ccf')
        carry_out()
    elif mn == 'bit':
        read(mode)
        e('ld (RV_N),a', 'ld l,a', 'and $40', 'ld (RV_V),a', 'ld a,(RV_A)', 'and l',
          'ld (RV_Z),a')
    elif mn in ('asl', 'lsr', 'rol', 'ror', 'inc', 'dec'):
        if mode == 'acc':
            e('ld a,(RV_A)')
            rmw_op(mn)
            e('ld (RV_A),a')
        else:
            fetch_ea(mode)
            if is_zp(mode):
                e('ld a,(hl)')
                e('push hl')
                rmw_op(mn)
                e('pop hl')
                if TRAPS_ZP:
                    a, b = lab(), lab()
                    e('ld (RV_T),a', 'ld a,l', 'cp 1', 'ld a,(RV_T)', 'jr z,%s' % a, 'ld (hl),a',
                      'jr %s' % b, '%s:' % a, 'call port_wr', 'ld (hl),a', '%s:' % b)
                else:
                    e('ld (hl),a')
            else:
                a, b, c2, d2 = lab(), lab(), lab(), lab()
                e('ld a,h', 'cp $40', 'jr nc,%s' % a, 'ld a,(hl)', 'push hl')
                rmw_op(mn)
                e('pop hl', 'ld (hl),a', 'jr %s' % b, '%s:' % a, 'call rd_hi', 'push hl')
                rmw_op(mn)
                e('pop hl', 'call wr_hi', '%s:' % b)
    elif mn in ('tax', 'tay', 'txa', 'tya', 'tsx'):
        e({'tax': 'ld a,(RV_A)', 'tay': 'ld a,(RV_A)', 'txa': 'ld a,b', 'tya': 'ld a,c',
           'tsx': 'ld a,(RV_S)'}[mn],
          {'tax': 'ld b,a', 'tay': 'ld c,a', 'txa': 'ld (RV_A),a', 'tya': 'ld (RV_A),a',
           'tsx': 'ld b,a'}[mn])
        setnz()
    elif mn == 'txs':
        e('ld a,b', 'ld (RV_S),a')
    elif mn in ('inx', 'iny', 'dex', 'dey'):
        r = 'b' if mn[2] == 'x' else 'c'
        e('%s %s' % ('inc' if mn[0] == 'i' else 'dec', r), 'ld a,%s' % r)
        setnz()
    elif mn in ('clc', 'sec'):
        e('xor a' if mn == 'clc' else 'ld a,$FF', 'ld (RV_C),a')
    elif mn == 'clv':
        e('xor a', 'ld (RV_V),a')
    elif mn in ('cli', 'sei', 'cld', 'sed'):
        e('ld hl,RV_P', '%s %d,(hl)' % ('set' if mn[1] == 'e' else 'res', 2 if mn[2] == 'i' else 3))
    elif mn in BR:
        var, test, skip = BR[mn]
        nt = lab()
        e('ld a,(%s)' % var, test, 'jr %s,%s' % (skip, nt), 'ld a,(de)', 'inc de', 'ld l,a',
          'add a,a', 'sbc a,a', 'ld h,a', 'add hl,de', 'ex de,hl')
        count()
        dispatch()
        e('%s:' % nt, 'inc de')
    elif mn == 'pha':
        e('ld a,(RV_A)', 'ld hl,(RV_S)', 'ld (hl),a', 'dec l', 'ld (RV_S),hl')
    elif mn == 'php':
        e('call pack_p', 'or $30', 'ld hl,(RV_S)', 'ld (hl),a', 'dec l', 'ld (RV_S),hl')
    elif mn == 'pla':
        e('ld hl,(RV_S)', 'inc l', 'ld (RV_S),hl', 'ld a,(hl)', 'ld (RV_A),a')
        setnz()
    elif mn == 'plp':
        e('ld hl,(RV_S)', 'inc l', 'ld (RV_S),hl', 'ld a,(hl)', 'call unpack_p')
    elif mn == 'jmp':
        e('ld a,(de)', 'inc de', 'ld l,a', 'ld a,(de)', 'ld h,a')
        if mode == 'ind':
            e('call rd_any', 'push af', 'inc l', 'call rd_any', 'ld h,a', 'pop af', 'ld l,a')
        e('call setpc')
        count()
    elif mn == 'jsr':
        e('ld a,(de)', 'inc de', 'ld l,a', 'ld a,(de)', 'ld h,a', 'push hl', 'call getpc',
          'ex de,hl', 'ld hl,(RV_S)', 'ld (hl),d', 'dec l', 'ld (hl),e', 'dec l', 'ld (RV_S),hl',
          'pop hl', 'call setpc')
        count()
    elif mn == 'rts':
        e('ld hl,(RV_S)', 'inc l', 'ld a,(hl)', 'inc l', 'ld h,(hl)', 'ld l,a', 'ld a,(RV_S)',
          'add a,2', 'ld (RV_S),a', 'inc hl', 'call setpc')
        count()
    elif mn == 'rti':
        e('ld hl,(RV_S)', 'inc l', 'ld a,(hl)', 'push hl', 'call unpack_p', 'pop hl', 'inc l',
          'ld a,(hl)', 'inc l', 'ld h,(hl)', 'ld l,a', 'ld a,(RV_S)', 'add a,3', 'ld (RV_S),a',
          'call setpc')
        count()
    elif mn == 'brk':
        e('inc de', 'call getpc', 'ex de,hl', 'ld hl,(RV_S)', 'ld (hl),d', 'dec l', 'ld (hl),e',
          'dec l', 'ld (RV_S),hl', 'call pack_p', 'or $30', 'ld hl,(RV_S)', 'ld (hl),a', 'dec l',
          'ld (RV_S),hl', 'ld hl,RV_P', 'set 2,(hl)', 'ld hl,$FFFE', 'call rd_any', 'push af',
          'inc l', 'call rd_any', 'ld h,a', 'pop af', 'ld l,a', 'call setpc')
        count()
    elif mn == 'nop':
        pass
    else:
        raise ValueError(mn)
    dispatch()
    return name


# patched-in opcodes (illegal on the 6502), handlers in machine.asm
SPECIAL = {0x02: 'h_idle', 0x12: 'h_mul', 0x32: 'h_sidcopy', 0x42: 'h_sprregs', 0x52: 'h_mask', 0x62: 'h_maskflip', 0x72: 'h_unpack'}


def main():
    out.append('; ---- generated by gen6502.py: do not edit ----')
    names = {}
    for op in sorted(OPS):
        mn, mode, _ = OPS[op]
        names[op] = handler(op, mn, mode)
    out.append('\tdefs (256 - ($ & 255)) & 255, 0')
    out.append('optab_lo:')
    for op in range(256):
        out.append('\tdb %s & 255' % (SPECIAL.get(op, names.get(op, 'emu_bad')) if not COUNT_ALL else names.get(op, 'emu_bad')))
    out.append('optab_hi:')
    for op in range(256):
        out.append('\tdb %s / 256' % (SPECIAL.get(op, names.get(op, 'emu_bad')) if not COUNT_ALL else names.get(op, 'emu_bad')))
    open(os.path.join(os.path.dirname(__file__), 'core.asm'), 'w').write('\n'.join(out) + '\n')
    print('core.asm: %d handlers%s' % (len(names), ' (COUNT_ALL)' if COUNT_ALL else ''))


if __name__ == '__main__':
    main()
