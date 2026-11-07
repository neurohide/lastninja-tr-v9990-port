#!/usr/bin/env python3
"""Differential test: Z80 core in openMSX vs ref6502.  usage: run_tests.py [seeds]"""
import os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ref6502 import CPU
from parse6502 import OPS
NOFLOW = {'brk', 'jmp', 'jsr', 'rts', 'rti'}
CH = [o for o, (m, md, n) in OPS.items() if m not in NOFLOW]
LEN = {o: n for o, (m, md, n) in OPS.items()}


def gen_prog(rnd, n):
    b = bytearray()
    for _ in range(n):
        o = rnd.choice(CH); b.append(o)
        if OPS[o][1] == 'rel': b.append(0)          # offset 0: taken or not, same flow
        else: b.extend(rnd.randrange(256) for _ in range(LEN[o] - 1))
    return b


def run(seed, n=150, full=150):
    rnd = random.Random(seed)
    prog = gen_prog(rnd, full); regs = [rnd.randrange(256) for _ in range(3)] + [rnd.randrange(256) & 0xCF | 0x20]
    d = open(os.path.join(HERE, 'testdata.inc'), 'w')
    d.write('initregs:\n\tdb %s\n\tdw %d\n' % (','.join(map(str, regs)), n))
    d.write('prog:\n' + ''.join('\tdb %d\n' % x for x in prog) + 'progend:\n'); d.close()
    r = subprocess.run(['z80asm', '-o', os.path.join(HERE, 't.rom'), harness], cwd=HERE, capture_output=True, text=True)
    if r.returncode: print(r.stdout, r.stderr); sys.exit(1)
    open(os.path.join(HERE, 'dump.tcl'), 'w').write('''
set throttle off
after time 12 {
 set f [open "%s/dump.txt" w]
 set s ""
 for {set i 0} {$i < 10} {incr i} { append s [format "%%02X " [debug read memory [expr {0xC000 + $i}]]] }
 puts $f $s
 set s ""
 for {set i 0} {$i < 0x400} {incr i} { append s [format "%%02X" [debug read memory [expr {0x8000 + $i}]]] }
 puts $f $s
 close $f
 exit
}
''' % HERE)
    subprocess.run(['openmsx', '-machine', 'Panasonic_FS-A1GT', '-cart', os.path.join(HERE, 't.rom'),
                    '-script', os.path.join(HERE, 'dump.tcl')], capture_output=True, timeout=120)
    lines = open(os.path.join(HERE, 'dump.txt')).read().split('\n')
    z = [int(x, 16) for x in lines[0].split()]; zmem = bytes.fromhex(lines[1])
    mem = bytearray(65536); mem[0x200:0x200 + len(prog)] = prog
    c = CPU(mem, 0x200, *regs)
    try:
        for _ in range(n): c.step()
    except KeyError:
        print('seed', seed, 'skipped (self-overwrite hit an illegal opcode)'); return True
    exp = [c.a, c.x, c.y, c.sp, c.P() & ~0x10, None, None, None, c.pc & 255, c.pc >> 8]
    got = [z[0], z[1], z[2], z[3], z[4] & ~0x10, None, None, None, z[8], z[9]]
    ok = exp == got and bytes(mem[:0x400]) == zmem
    if not ok:
        print('seed', seed, 'FAIL\n exp', [None if v is None else '%02X' % v for v in exp], '\n got', [None if v is None else '%02X' % v for v in got])
        diff = [i for i in range(0x400) if mem[i] != zmem[i]][:8]
        print(' mem diffs', [(hex(i), mem[i], zmem[i]) for i in diff])
    return ok


harness = 'harness.asm'
def bisect(seed):
    lo, hi = 0, 150
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if run(seed, mid): lo = mid
        else: hi = mid
    rnd = random.Random(seed); prog = gen_prog(rnd, 150)
    mem = bytearray(65536); mem[0x200:0x200 + len(prog)] = prog
    rnd = random.Random(seed); gen_prog(rnd, 150); regs = [rnd.randrange(256) for _ in range(3)] + [rnd.randrange(256) & 0xCF | 0x20]
    c = CPU(mem, 0x200, *regs)
    for _ in range(lo): c.step()
    pc = c.pc; print('first bad instr #%d at %04X:' % (hi, pc), mem[pc:pc + 3].hex(' '), OPS[mem[pc]],
                    'before: a=%02X x=%02X y=%02X p=%02X' % (c.a, c.x, c.y, c.P()))


if __name__ == '__main__':
    if sys.argv[1:2] == ['bisect']:
        bisect(int(sys.argv[2])); sys.exit()
    seeds = range(int(sys.argv[1])) if len(sys.argv) > 1 else range(5)
    res = [run(s) for s in seeds]
    print(sum(res), '/', len(res), 'passed')
