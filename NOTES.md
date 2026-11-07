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
