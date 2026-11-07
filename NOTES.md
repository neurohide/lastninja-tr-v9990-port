# Last Ninja (C64) -> MSX turbo R + V9990 : working notes

Project scaffolded from `~/Sources/buggyboymsx` (`msx/`, `tools/` copied unchanged; they still hold Buggy Boy code and the old `msx/build/` outputs). Originals: `disk/*.d64`.

## C64 boot flow (side 1, found by tracing in VICE)
1. `the last ninja` (PRG, SYS 2061): stage-1 depacker -> intro at `$0800` (spin at `$0884`, space = `$DC01==$EF` -> `jmp $088B`).
2. `$088B` copies a 40-byte relocator to `$033C`: moves `$2200`.. (210 pages) to `$0800`, jumps `$080D`. Stage 2 is packed again (depacker copied to `$00FC`), ends at title-key wait.
3. Cracktro menu: `GETIN` wait for `D`/`E` (`$A343`), then ~12 Y/N trainer prompts (`$A395`, N=`$4E`), then title screen `$CB00` waits for joystick fire (`$DC00` bit 4, `bne $CB5B` at `$CB6D`).
4. Game then loads files via KERNAL `SETNAM/SETLFS/LOAD` (routine `$C800`; name at `$04F0`: `LA1`, `LA2`...; loader/depacker overlay `hf` at `$C800`). Level files `la1..lf4` are crunched streams.

## Dump recipe (VICE remote monitor, `x64sc -warp -remotemonitor ... -autostart s1.d64`)
`g 088b` -> poke key `> 0277 44` + `> c6 01` (D) -> answer prompts with `4e` x ~14 -> patch `> cb6d ea ea` to skip fire wait -> `save "f" 0 0000 ffff`.
Result: `dumps/game_run.bin` (RAM with level 1 loaded; game running at ~`$BD16`/`$5293`).

## Next
- Disassemble/trace `dumps/game_run.bin` (tools/trace.py style) to find real game code; game uses IRQ + indirect dispatch.
- Replace Buggy Boy specifics in translator/kernel; KERNAL LOAD -> MSX-DOS file read; V9990 renderer for sprites/multicolor; PSG/SCC for SID.

## Status (this session)
- `disasm/game.info` + `disasm/game.s`: trace of `dumps/game_run.mem` from `$BD16`: 6293 instructions, 12.9 KB code, IRQ handlers `$5533`, `$554d` (via `tools/trace.py dumps/game_run.mem 0x0800 0xFFFF 0xBD16 ...`). Code reached by jump tables / self-modification still shown as data.
- NOT done: translator is still the Buggy Boy one (reads `disasm/game.s` of that game), kernel/renderer/loader unchanged, no MSX-DOS disk, no ROM built.

## Findings: translator reuse (blockers)
- `msx/tools/c64image.py` is Buggy Boy specific: reads that game's `disasm/game.s` comments, hard-coded `GAME_START`, `IRQ_HANDLERS`, `JUMP_TABLES`, `PATCHES`, `RAM_MODE_RANGES`; `translate.py` has `ESCAPE_JUMPS`, `IO_FAST`. All must be re-derived for this dump.
- Memory model clash: translator maps Z80 `$4000-$7FFF` to a translated-code window and treats C64 `$4000-$7FFF` as the VIC bank (separate segment). Last Ninja has ~10 KB of its ~12.9 KB traced code at C64 `$5000-$7FFF`, plus data there. Model needs redesign (code window elsewhere / segments per C64 page).
- Code is overlaid per level (files loaded to `$2209`, `$b114`, `$010b`...), so each level's code variant needs its own translation, and the in-game loader/depacker must run translated.
- Bug fixed: first `disasm/game.s` was based at `$0800` instead of `$0000` (misaligned); regenerated with `STARTADDR $0000`.

## Step 2 (partial): c64image.py retargeted
`msx/tools/c64image.py` now loads `dumps/game_run.mem`, `GAME_START=$BD16`, IRQ `$5533/$554D`, no patches/jump tables/RAM-mode ranges. Tracer tolerates bad paths (logged in `BAD`). Result: 6409 instrs, 13153 B code, 10 bad paths: jsr to KERNAL `$FFC0-$FFEA` (need k_ stubs: SETLFS/SETNAM/LOAD...), `$C843/$C846` (hf overlay not in this dump), 1 overlap at `$BCB3/$BCB1` (BIT-skip trick or data).
Still TODO: jump tables (none found yet), memory model for code at `$5000-$7FFF`, kernel/renderer rewrite, MSX-DOS loader, ROM build.

## Step 3: translator blockers on Last Ninja image
- Opcode-modifying stores: `$BCB6`->`$BC66` (main-loop `jsr` table patched at runtime; loop at `$BCB1-$BCBA` overlaps `jsr $BD66` = mid-instruction branch target `$BCB3`); `$0442/$0445/$044A` patch the hf loader stubs. `translate.py` now logs these in `OPMOD` instead of raising; tracer keeps overlapping decodes (`BAD` logs them).
- Unsupported 6502 ops (translator never needed them for Buggy Boy): `bit`x19, `php`x5, `plp`x8, `bvs`x3, `bvc`x1, `brk`x3. Needs a V flag (also set by ADC/SBC) and PHP/PLP flag packing. First hard stop: `unhandled bit at 76BF`.
- Not started: memory-model change, kernel/renderer, MSX-DOS loader, ROM.

## Emulation route (chosen)
`emu/`: 6502 interpreter for Z80/R800.
- `gen6502.py` -> `core.asm` (151 documented opcodes incl. bit/php/plp/bvs/bvc/brk, V flag; no decimal mode). 6502 PC in DE, regs in RAM (`RV_*`), 64K 6502 memory = 4 mapper segments via Z80 page 2. Unoptimised (call per memory access).
- `ref6502.py`: Python reference CPU. `run_tests.py N`: random 150-instr programs, core run in openMSX (FS-A1GT) via `harness.asm`, regs + `$0000-$03FF` compared. `run_tests.py bisect S` finds first diverging instruction.
- Status: 40/40 seeds pass (3 skipped where random code overwrote itself into illegal opcodes).
- Next: load `dumps/game_run.mem` into the 4 segments, start at `$BD16`, add I/O traps for `$D000-$DFFF` (VIC/SID/CIA), raster IRQ, KERNAL LOAD -> MSX-DOS, V9990 output; then speed (inline zero-page/stack access, R800).

## Emulator status (emu/)
- Boot state: `dumps/state.json` + `state_ram.mem` + `state_io.mem`, captured in VICE mid-game (PC `$BD14`, port `$35`, raster IRQ line 8, CIA1 timer A latch `$4800`). `$5400` is NOT a valid entry for a mid-game dump (`$048A` turns all IRQs off before it; level code at `$BC66` already replaced).
- `machine.asm`: I/O traps ($D000-$DFFF when port shows I/O), CPU port, VIC raster IRQ + IMR/IRR, CIA1 timer A + ICR, IRQ entry (hardware `$FFFE` or KERNAL-style via `$0314`), scheduler = 1 raster line per 16 instructions, 312 lines/frame.
- `video.asm`: V9990 B3 512px 4bpp, palette = C64 colours; multicolour bitmap ($C000 screen, $E000 bitmap, colour RAM) redrawn every 4 emulated frames; MSX joystick 1 / cursor+space -> `$DC00`.
- Verified: screen matches reference VIC render of the dump; game keeps running (IRQs ~2/frame, `$1B` advances).
- Speed: ~1 emulated frame/s (~5k 6502 instr/s) vs 50 needed. Core unoptimised.
- TODO: sprites, speed, SID->PSG, KERNAL LOAD -> MSX-DOS disk (level change), keyboard matrix ($DC01), title/menu screens (fixed VIC bank in renderer).
- `RENDER_TEST=1 python3 emu/build.py`: render captured screen once and halt (renderer check).

## Speed pass (emu/)
- Core rewrite: Z80 pages all RAM (P0 = 6502 $0000-$3FFF direct, P1 = core copy, P2 = window, P3 = system); PC = Z80 pointer in DE; X/Y in B/C; lazy flags (RV_N/Z/C/V); inline dispatch; slice counter on control flow only (SLICE=4 per raster line). `embuild.py` (was build.py), `run_tests.py` uses the same machine in TEST mode: 40/40 seeds pass.
- Idle skip: game patch `$BD19 F0->02`; opcode `$02` (h_idle) fast-forwards straight to the next event (frame end, raster compare, timer underflow). CIA timer A is counted in raster lines.
- Dirty pages: writes to VIC bank 3 ($C000-$FFFF, except sprite pointers $C3F8-$C3FF) and colour RAM mark 256-byte pages; renderer redraws only touched character rows.
- Result: ~1.3 -> ~55 emulated frames/s; now throttled to 50 Hz on the turbo R system timer (`frame_sync`, THROTTLE=0 to disable). `emu/prof.sh N` = PC profile (6502 + Z80 routines).
- Not yet known: frame rate in busy scenes (fights, many enemies), since there is no input test yet.

## Sprites (emu/video.asm)
- Screen now B3 8 bpp: palette 0-15 background, 16-31 sprite copies (so black sprite pixels are not blitter-transparent). Background rendered into a clean copy at VRAM y 256, changed rows blitted to the display (y 0).
- Per render: old sprite boxes restored from the clean copy (LMMM), sprites 7..0 drawn as LMMM with transparency from a VRAM sprite cache (64 slots of 72x42 at y 512+, key = pointer/flags/colours, re-decoded when its data page was written: SDIRTY flags set by wr_hi).
- MC/hires, X/Y expand, clipping to the 480x200 window. Not done: sprite-background priority ($D01B), collisions, multiplexing.
- Verified: ninja drawn and walks with cursor keys; 50 frames/s with input.
- Open question: POWER/WEAPONRY panels empty in both our render and the reference render of the dump; compare with a VICE screenshot.

## Disk loading (emu/kernal.asm, emu/mkdsk.py)
- `emu/mkdsk.py` -> `emu/lastninja.dsk`: 720K FAT12 MSX-DOS disk with the original C64 files from `disk/c64/` (HF, LA1..LF4; contents unchanged, PRG load address kept).
- Boot: cartridge init only hooks H.STKE (CALLF into the ROM); the emulator starts after the disk ROM is up. Z80 stack moved to $E400 (HIMEM is $E5A8 on the FS-A1GT).
- DOS bridge (page 3, $C800): page 0 back to the BIOS slot, page 2 to its original segment, EI, BDOS FCB call, DI, restore.
- KERNAL traps: setpc -> kernal_trap for targets $E000-$FFFF while the KERNAL is mapped. Done: SETMSG SETLFS SETNAM OPEN CLOSE CHKIN CLRCHN CHRIN READST LOAD GETIN CHROUT CLALL, $F642. Unknown address: halt with it in k_bad ($C890).
- Level load check: `LOADTEST=1 python3 emu/embuild.py` runs `jsr $0400` (LOAD "HF") + `jsr $0450` (hf streams LA1 via CHRIN and depacks); RAM afterwards equals `emu/ref_load.py` (same load on ref6502) byte for byte.
- Not yet seen: a real level change triggered by the game itself (needs playing to the end of level 1).
