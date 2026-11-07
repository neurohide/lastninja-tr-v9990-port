#!/usr/bin/env python3
"""Build emu/lastninja.rom (ASCII16): bank 0 = machine.asm, banks 1-4 = C64 RAM, bank 5 = C64 I/O.
Env: RENDER_TEST=1 renders the captured screen once and halts."""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def build(sym, ram, io, out, test=False):
    subprocess.run([sys.executable, os.path.join(HERE, 'gen6502.py'), '1' if test else '0'], check=True,
                   stdout=subprocess.DEVNULL)
    sym = dict(sym, TEST=int(test), TRAPS=int(not test), RENDER_EVERY=2, THROTTLE=int(os.environ.get('THROTTLE', '1')), AUTOWALK=int(os.environ.get('AUTOWALK', '0')), STOPFRAME=int(os.environ.get('STOPFRAME', '0')),
               RENDER_TEST=int(os.environ.get('RENDER_TEST', '0')))
    open(os.path.join(HERE, 'state.inc'), 'w').write(''.join('%s:\tequ $%04X\n' % kv for kv in sym.items()))
    r = subprocess.run(['z80asm', '-o', 'machine.bin', '-Lmachine.lbl', 'machine.asm'], cwd=HERE,
                       capture_output=True, text=True)
    if r.returncode:
        print(r.stdout, r.stderr); sys.exit(1)
    code = open(os.path.join(HERE, 'machine.bin'), 'rb').read()
    assert len(code) <= 0x4000, 'bank 0 overflow: %d' % len(code)
    rom = code.ljust(0x4000, b'\xff') + bytes(ram[:0x10000]) + bytes(io).ljust(0x4000, b'\0')
    open(out, 'wb').write(rom.ljust(0x20000, b'\xff'))
    return len(code)


# address -> (original, new).  $02 = beq that fast-forwards to the next IRQ.
PATCHES = {0xBD19: (0xF0, 0x02),   # main loop: wait for $1B (frame counter) to change
           0x687E: (0x86, 0x12),   # 8x8 multiply -> native
           0xB00B: (0xA2, 0x32),   # music player SID register copy -> native
           0x5690: (0xA0, 0x42)}   # IRQ sprite register update -> native


def game():
    st = json.load(open(os.path.join(ROOT, 'dumps', 'state.json')))
    h = lambda k: int(st[k], 16)
    sym = dict(START_PC=h('pc'), START_PORT=h('port'), ST_A=h('a'), ST_X=h('x'), ST_Y=h('y'), ST_S=h('s'),
               ST_P=h('p'), ST_CMP=st['raster_cmp'], ST_IMR=h('imr'), ST_MASK=h('cia1_mask'),
               ST_CRA=h('cia1_cra'), ST_TLAT=h('cia1_latch'), ST_TCNT=h('cia1_count'), ST_N=0)
    ram = bytearray(open(os.path.join(ROOT, 'dumps', 'state_ram.mem'), 'rb').read())
    nohle = os.environ.get('NOHLE')
    for a, (old, new) in PATCHES.items():
        if nohle and new != 0x02:
            continue
        assert ram[a] == old, 'patch %04X: %02X' % (a, ram[a])
        ram[a] = new
    io = open(os.path.join(ROOT, 'dumps', 'state_io.mem'), 'rb').read()
    if os.environ.get('LOADTEST'):           # load level part 1 through the game's loader, then stop
        stub = bytes([0x20, 0x00, 0x04, 0x20, 0x50, 0x04, 0x4C, 0x46, 0x03])   # $0340: jsr $0400 (HF) / jsr $0450 / jmp $0346
        ram[0x340:0x349] = stub
        ram[0x4F2] = ord('1')
        sym['START_PC'] = 0x340
    n = build(sym, ram, io, os.path.join(HERE, 'lastninja.rom'))
    print('lastninja.rom: bank0 %d bytes' % n)


if __name__ == '__main__':
    game()
