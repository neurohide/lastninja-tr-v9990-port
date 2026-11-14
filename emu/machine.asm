; Last Ninja on MSX turbo R: C64 machine around the generated 6502 core.
; ROM: ASCII16, bank 0 = this code, banks 1-4 = C64 RAM image,
; bank 5 = C64 I/O page ($D000-$DFFF) captured in VICE.
;
; Running layout (all RAM, set up by boot_rt):
;   page 0 = SEG0     6502 $0000-$3FFF (direct)
;   page 1 = SEG_CORE copy of bank 0 (this code)
;   page 2 = window: SEG0+1..SEG0+3 (6502 $4000-$FFFF), SEG_IO, renderer
;   page 3 = system RAM: RV_* vars, Z80 stack
; Timing: one raster line per SLICE control-flow instructions.
; TEST=1: differential-test build (no I/O, stops after ST_N instructions).

	include "state.inc"

SEG0:		equ 4
SEG_IO:		equ 8
SEG_CORE:	equ 9
PORT_P0:	equ $FC
PORT_P1:	equ $FD
PORT_P2:	equ $FE
CHGCPU:		equ $0180
RSLREG:		equ $0138
EXPTBL:		equ $FCC1
ASCII16_P1:	equ $6000
SLICE:		equ 8
LINES:		equ 312
CYC_LINE:	equ 63

RV:		equ $C000
RV_A:		equ RV+0
RV_T:		equ RV+1
RV_S:		equ RV+2	; RV+3 is always $01 (stack page)
RV_P:		equ RV+4	; I, D
RV_N:		equ RV+5
RV_Z:		equ RV+6
RV_C:		equ RV+7
RV_V:		equ RV+8
RV_CNT:		equ RV+9
RV_CODESEG:	equ RV+10	; segment in page 2 for code fetch
RV_IO:		equ RV+11	; 1 = I/O visible at $D000
RV_KERN:	equ RV+12	; 1 = KERNAL visible (IRQ via $0314)
RV_PORT:	equ RV+13	; CPU port $01
RV_LINE:	equ RV+14	; 2
RV_FRAMES:	equ RV+16	; 2
RV_CMP:		equ RV+18	; 2
RV_IRR:		equ RV+20
RV_IMR:		equ RV+21
RV_ICR:		equ RV+22
RV_MASK:	equ RV+23
RV_CRA:		equ RV+24
RV_TCNT:	equ RV+26	; 2 timer A: raster lines to underflow
RV_TLAT:	equ RV+28	; 2
RV_NIRQ:	equ RV+30	; 2
rd_bg:		equ RV+32
rd_row:		equ RV+33
rd_line:	equ RV+34
rd_r40:		equ RV+36	; 2
rd_bm:		equ RV+38	; 2
RV_X:		equ RV+40	; test results
RV_Y:		equ RV+41
RV_PC:		equ RV+42	; 2
RV_PP:		equ RV+44
RV_RAMPRIM:	equ RV+46
RV_RAMSUB:	equ RV+47	; $FF = not expanded
rd_lastbg:	equ RV+48
RV_TLATL:	equ RV+50	; 2 timer A reload in raster lines
RV_DEADLINE:	equ RV+52	; 2 system timer value of the next frame start
RV_LATE:	equ RV+54	; 2 frames we were late (debug)
RV_RTICKS:	equ RV+58	; 2 debug: system timer ticks spent in render (wraps)
RV_STICKS:	equ RV+60	; 2 debug: ticks spent in sound_update
RV_SKIP:	equ RV+62	; renders skipped in a row
RV_NSKIP:	equ RV+63	; 2 debug: renders skipped in total
RV_DACC:	equ RV+65	; dissolve: tenths of raster lines carried over
RV_VDIRTY:	equ RV+66	; background screen/bitmap/colour data changed
RV_CODEHI:	equ RV+56	; bits 7-6 of code addresses for the inline fast path ($00 in segment 7)
TICKS_FRAME:	equ 5114		; 20 ms in 3.911 us system timer ticks
BOOTRT:		equ $C100
DOSRT:		equ $C800		; DOS bridge (copied to page 3)
FCB:		equ $C8C0		; 37 bytes
FBUF:		equ $D000		; 4K file buffer
FBUF_LEN:	equ $1000
STACK:		equ $E400		; below HIMEM ($E5A8 with the disk system)
H_STKE:		equ $FEDA
SLTTBL:		equ $FCC5
BDOS:		equ $F37D
KV:		equ $C880		; KERNAL emulation variables
k_dev:		equ KV+0
k_sa:		equ KV+1
k_fnlen:	equ KV+2
k_open:		equ KV+3	; 1 = FCB open
k_eof:		equ KV+4	; 1 = last block read
k_pos:		equ KV+6	; 2
k_len:		equ KV+8	; 2
k_addr:		equ KV+10	; 2 LOAD address
k_romslot:	equ KV+12
k_a8:		equ KV+13	; A8 at start (page 0 = BIOS slot)
k_p2seg:	equ KV+14	; mapper segment of page 2 at start
k_bad:		equ KV+16	; 2 unknown KERNAL address (debug)
k_fname:	equ KV+20	; 16
DIRTY:		equ $C400		; 64 flags: VIC bank 3 pages ($C000-$FFFF)

	org $4000
	db "AB"
	dw init
	dw 0, 0, 0
	defs 6,0

init:
	if TEST = 0
	; run from H.STKE (after the disk ROM has initialised): CALLF to start
	call RSLREG
	rrca
	rrca
	and 3
	ld c,a
	ld b,0
	ld hl,EXPTBL
	add hl,bc
	ld a,(hl)
	and $80
	or c
	ld c,a
	jr z,in_slot
	ld hl,SLTTBL
	ld e,c
	res 7,e
	ld d,0
	add hl,de
	ld a,(hl)
	and $0C
	or c
	ld c,a
in_slot:
	ld hl,H_STKE
	ld (hl),$F7		; rst $30
	inc hl
	ld (hl),c
	inc hl
	ld (hl),start & 255
	inc hl
	ld (hl),start / 256
	inc hl
	ld (hl),$C9
	ret
start:
	ld a,$C9
	ld (H_STKE),a
	in a,($A8)
	ld (k_a8),a
	in a,(PORT_P2)
	ld (k_p2seg),a
	ld a,$81		; R800 ROM mode
	call CHGCPU
	endif
	; slot of RAM = slot of page 3
	call RSLREG
	rlca
	rlca
	and 3
	ld (RV_RAMPRIM),a
	ld c,a
	ld b,0
	ld hl,EXPTBL
	add hl,bc
	ld a,(hl)
	and $80
	ld a,$FF
	jr z,in_noexp
	ld a,($FFFF)
	cpl
	rlca
	rlca
	and 3
in_noexp:
	ld (RV_RAMSUB),a
	di
	ld sp,STACK
	ld hl,dos_rt
	ld de,DOSRT
	ld bc,dos_end-dos_rt
	ldir
	ld hl,boot_rt
	ld de,BOOTRT
	ld bc,boot_end-boot_rt
	ldir
	jp BOOTRT

; ---- runs from page 3: copy ROM banks to RAM, switch pages 0/1 to RAM ----
boot_rt:
	ld b,0
br_loop:			; banks 1-5 -> SEG0..SEG0+4
	ld a,b
	add a,SEG0
	out (PORT_P2),a
	ld a,b
	inc a
	ld (ASCII16_P1),a
	push bc
	ld hl,$4000
	ld de,$8000
	ld bc,$4000
	ldir
	pop bc
	inc b
	ld a,b
	cp 5
	jr nz,br_loop
	xor a			; bank 0 (this code) -> SEG_CORE
	ld (ASCII16_P1),a
	ld a,SEG_CORE
	out (PORT_P2),a
	ld hl,$4000
	ld de,$8000
	ld bc,$4000
	ldir
	ld a,SEG0
	out (PORT_P0),a
	ld a,SEG_CORE
	out (PORT_P1),a
	ld a,(RV_RAMPRIM)
	ld b,a
	rlca
	rlca
	or b
	ld b,a
	in a,($A8)
	and $F0
	or b
	out ($A8),a
	ld a,(RV_RAMSUB)
	cp $FF
	jr z,br_done
	ld b,a
	rlca
	rlca
	or b
	ld b,a
	ld a,($FFFF)
	cpl
	and $F0
	or b
	ld ($FFFF),a
br_done:
	jp init2
boot_end:

; ---- DOS bridge: runs from page 3 (page 1 is swapped by the disk ROM) --------
; call DOSRT with C = BDOS function, DE/HL = parameters; returns A, HL.
; Page 0 goes back to the BIOS slot and page 2 to its original segment for the
; call (interrupts on, BIOS ISR), then pages 0/2 return to the emulator.
dos_rt:
	push hl
	in a,($A8)
	and $FC
	ld l,a
	ld a,(k_a8)
	and 3
	or l
	out ($A8),a
	ld a,(k_p2seg)
	out (PORT_P2),a
	pop hl
	push ix
	push iy
	ei
	call BDOS
	di
	pop iy
	pop ix
	push af
	push hl
	in a,($A8)
	and $FC
	ld l,a
	ld a,(RV_RAMPRIM)
	or l
	out ($A8),a
	ld a,(RV_CODESEG)
	out (PORT_P2),a
	pop hl
	pop af
	ret
dos_end:

; ---- now running from RAM ---------------------------------------------------
init2:
	if TEST = 0
	call v_init
	call psg_init
	call dirty_all
	ld a,$FF
	ld (rd_lastbg),a
	endif
	if RENDER_TEST
	call render
rt_halt:
	jr rt_halt
	endif
	ld hl,RV
	ld b,46
in_clr:
	ld (hl),0
	inc hl
	djnz in_clr
	ld a,1
	ld (RV_S+1),a
	ld a,ST_S
	ld (RV_S),a
	ld a,ST_A
	db $FD,$6F		; ld iyl,a (6502 A)
	ld a,ST_P
	call unpack_p
	ld hl,ST_CMP
	ld (RV_CMP),hl
	ld a,ST_IMR
	ld (RV_IMR),a
	ld a,ST_MASK
	ld (RV_MASK),a
	ld a,ST_CRA
	ld (RV_CRA),a
	ld hl,ST_TLAT
	ld (RV_TLAT),hl
	call tlat_lines
	ld hl,ST_TCNT
	call div63
	ld (RV_TCNT),hl
	if TEST
	ld a,ST_N
	else
	ld a,START_PORT
	call port_wr
	ld (1),a
	ld a,SLICE
	endif
	ld (RV_CNT),a
	if TEST = 0
	ld hl,0
	ld (RV_LATE),hl
	call sys_timer
	ld (RV_DEADLINE),hl
	endif
	xor a
	ld (RV_CODEHI),a
	ld hl,START_PC
	call setpc
	ld b,ST_X
	ld c,ST_Y
	jp core_dispatch

; ---- PC conversion ----------------------------------------------------------
; HL = 6502 address -> DE = Z80 pointer, page 2 mapped.  Keeps BC.
; shortcut: code running across $3FFF/$4000 or a 16K window edge is not
; re-mapped (only jumps/branch targets are); fine for this game so far.
setpc:
	ld a,h
	cp $40
	jr nc,sp_hi
	ld d,h
	ld e,l
	ret
sp_hi:
	if TRAPS
	cp $E0
	jr c,sp_ram
	call port_kern
	jp nz,kernal_trap
	ld a,h
sp_ram:
	endif
	rlca
	rlca
	and 3
	add a,SEG0
	ld (RV_CODESEG),a
	out (PORT_P2),a
	cp SEG0+3		; segment 7 holds I/O, screen, sprites: no fast path
	ld a,h
	jr nz,sp_fast
	xor a
sp_fast:
	and $C0
	ld (RV_CODEHI),a
	ld a,h
	and $3F
	or $80
	ld d,a
	ld e,l
	ret

; DE -> HL = 6502 address.  Keeps BC, DE.
getpc:
	ld a,d
	cp $40
	jr nc,gp_hi
	ld h,d
	ld l,e
	ret
gp_hi:
	ld a,(RV_CODESEG)
	sub SEG0
	rrca
	rrca
	ld h,a
	ld a,d
	and $3F
	or h
	ld h,a
	ld l,e
	ret

; ---- memory above $4000 (page-2 window) ---------------------------------
; rd_hi: HL -> A.  wr_hi: A -> (HL).  Both keep BC, DE, HL and re-map code.
rd_hi:
	if TRAPS
	ld a,h
	cp $D0
	jr c,rh_ram
	cp $E0
	jr nc,rh_ram
	call port_io
	jr z,rh_ram
	call io_rd
	jr rh_back
	endif
rh_ram:
	push hl
	ld a,h
	rlca
	rlca
	and 3
	add a,SEG0
	ld hl,RV_CODESEG	; same segment as the code: no re-mapping
	cp (hl)
	pop hl
	jr z,rh_same
	push hl
	out (PORT_P2),a
	ld a,h
	and $3F
	or $80
	ld h,a
	ld a,(hl)
	pop hl
rh_back:
	push af
	ld a,(RV_CODESEG)
	out (PORT_P2),a
	pop af
	ret
rh_same:
	push hl
	ld a,h
	and $3F
	or $80
	ld h,a
	ld a,(hl)
	pop hl
	ret

wr_hi:
	ld (RV_T),a
	if TRAPS
	ld a,h
	cp $D0
	jr c,wh_ram
	cp $E0
	jr nc,wh_ram
	call port_io
	jr z,wh_ram
	ld a,(RV_T)
	call io_wr
	jr wh_back
	endif
wh_ram:
	push hl
	ld a,h
	cp $C0
	jr c,wh_nod
	cp $C3			; $C3F8-$C3FF: sprite pointers, not drawn as screen
	jr nz,wh_mark
	ld a,l
	cp $F8
	ld a,h
	jr nc,wh_nod
wh_mark:
	; Only pages used by the bitmap background need a character-row scan.
	; Sprite data pages still invalidate the sprite cache below.
	ld a,h
	cp $C4
	jr c,wh_bgdirty
	cp $E0
	jr c,wh_page
wh_bgdirty:
	ld a,1
	ld (RV_VDIRTY),a
	ld a,h
wh_page:
	sub $C0			; VIC bank 3 page -> dirty flags (screen, sprites)
	ld l,a
	ld h,DIRTY/256
	ld (hl),1
	set 6,l
	ld (hl),1
	pop hl
	push hl
	ld a,h
wh_nod:
	rlca
	rlca
	and 3
	add a,SEG0
	ld hl,RV_CODESEG
	cp (hl)
	pop hl
	push hl
	jr z,wh_same
	out (PORT_P2),a
	ld a,h
	and $3F
	or $80
	ld h,a
	ld a,(RV_T)
	ld (hl),a
	pop hl
wh_back:
	ld a,(RV_CODESEG)
	out (PORT_P2),a
	ld a,(RV_T)
	ret
wh_same:
	ld a,h
	and $3F
	or $80
	ld h,a
	ld a,(RV_T)
	ld (hl),a
	pop hl
	ret

rd_any:				; HL -> A, any address
	ld a,h
	cp $40
	jp nc,rd_hi
	ld a,(hl)
	ret

; ---- flags: P <-> lazy flag bytes.  Use A and L. ---------------------------
pack_p:				; -> A (bit 4 and 5 clear)
	ld a,(RV_P)
	and $0C
	ld l,a
	db $DD,$7C		; ld a,ixh (N source)
	and $80
	or l
	ld l,a
	ld a,(RV_V)
	or a
	jr z,pp_v
	set 6,l
pp_v:
	db $DD,$7D		; ld a,ixl (Z source)
	or a
	jr nz,pp_z
	set 1,l
pp_z:
	ld a,(RV_C)
	and 1
	or l
	ret

unpack_p:			; A = P
	ld l,a
	and $0C
	ld (RV_P),a
	ld a,l
	and $40
	ld (RV_V),a
	ld a,l
	rra
	sbc a,a
	ld (RV_C),a
	ld a,l
	and $80
	db $DD,$67		; ld ixh,a (N source)
	ld a,l
	and 2
	xor 2
	db $DD,$6F		; ld ixl,a (Z source)
	ret

; ---- CPU port: the 6502 writes $0001 as plain RAM (page 0); the memory map
; is worked out from it only where it matters.  Use A only.
port_io:			; NZ if I/O is visible at $D000
	ld a,($0001)
	bit 2,a
	ret z
	and 3
	ret
port_kern:			; NZ if the KERNAL is visible at $E000
	ld a,($0001)
	and 2
	ret

; ---- CPU port ($0001) write: A = value, keeps all but F -------------------
port_wr:
	push af
	push bc
	ld (RV_PORT),a
	ld b,a
	and 2
	rrca
	ld (RV_KERN),a
	ld a,b
	and 3
	jr z,pw_noio
	ld a,b
	and 4
	jr z,pw_noio
	ld a,1
	jr pw_set
pw_noio:
	xor a
pw_set:
	ld (RV_IO),a
	pop bc
	pop af
	ret

; ---- I/O shadow address: HL ($Dxxx) -> HL in page 2, maps SEG_IO ----------
io_map:
	ld a,SEG_IO
	out (PORT_P2),a
	ld a,h
	and $0F
	or $80
	ld h,a
	ret

; ---- I/O read: HL = $D000-$DFFF -> A ; keeps HL,BC,DE ---------------------
io_rd:
	push hl
	push bc
	ld a,h
	cp $D4
	jr c,ir_vic
	cp $DC
	jr z,ir_cia1
	cp $DE
	jr nc,ir_ff
ir_shadow:
	call io_map
	ld a,(hl)
ir_done:
	pop bc
	pop hl
	ret
ir_ff:
	ld a,$FF
	jr ir_done
ir_vic:
	ld a,l
	and $3F
	ld l,a
	ld h,$D0
	cp $11
	jr z,ir_d011
	cp $12
	jr z,ir_d012
	cp $19
	jr z,ir_d019
	cp $1E
	jr nc,ir_coll
	jr ir_shadow
ir_d011:
	call io_map
	ld a,(hl)
	and $7F
	ld b,a
	ld a,(RV_LINE+1)
	rrca
	and $80
	or b
	jr ir_done
ir_d012:
	ld a,(RV_LINE)
	jr ir_done
ir_d019:
	ld a,(RV_IRR)
	or $70
	jr ir_done
ir_coll:
	xor a			; shortcut: no sprite collisions
	jr ir_done
ir_cia1:
	ld a,l
	and $0F
	jr z,ir_joy		; port A: joystick 2
	cp 1
	jr z,ir_ff		; port B: keyboard rows (TODO)
	cp 4
	jr z,ir_ta_lo
	cp 5
	jr z,ir_ta_hi
	cp $0D
	jr nz,ir_shadow
	ld a,(RV_ICR)
	ld b,a
	xor a
	ld (RV_ICR),a
	ld a,b
	jr ir_done
ir_joy:
	call joy_read
	jr ir_done
ir_ta_lo:
	call tcnt_cycles
	ld a,l
	jr ir_done
ir_ta_hi:
	call tcnt_cycles
	ld a,h
	jr ir_done

; ---- I/O write: A = value, HL = $D000-$DFFF ; keeps HL,BC,DE --------------
io_wr:
	push hl
	push bc
	ld c,a
	ld a,SEG_IO		; (the caller re-maps the code segment)
	out (PORT_P2),a
	ld a,h
	cp $D4
	jr c,iw_vicw
	cp $D8
	jr c,iw_sidw
	cp $DC
	jr c,iw_colw
	ld b,a			; $DC00-$DFFF: CIA1, CIA2, expansion
	and $0F
	or $80
	ld h,a
	ld (hl),c
	ld a,b
	cp $DC
	jp z,iw_cia1
	jr iw_done
iw_vicw:			; VIC: mirror every 64 bytes
	ld a,l
	and $3F
	ld l,a
	ld h,$80
	ld (hl),c
	jr iw_vic
iw_sidw:			; SID: mirror every 32 bytes, gate transitions
	ld a,l
	and $1F
	ld l,a
	ld h,$84
	cp 4
	jr z,iw_gate
	cp 11
	jr z,iw_gate
	cp 18
	jr z,iw_gate
	ld (hl),c
	jr iw_done
iw_gate:
	ld b,(hl)		; old value
	ld (hl),c
	call sid_gate
	jr iw_done
iw_colw:			; colour RAM: dirty page flags $18-$1B
	ld a,1
	ld (RV_VDIRTY),a
	ld a,h
	push hl
	sub $C0
	ld l,a
	ld h,DIRTY/256
	ld (hl),1
	pop hl
	ld a,h
	and $0F
	or $80
	ld h,a
	ld (hl),c
iw_done:
	ld a,c
	pop bc
	pop hl
	ret
iw_vic:
	ld a,l
	cp $11
	jr z,iw_d011
	cp $12
	jr z,iw_d012
	cp $19
	jr z,iw_d019
	cp $1A
	jr z,iw_d01a
	jr iw_done
iw_d011:
	ld a,c
	rlca
	and 1
	ld (RV_CMP+1),a
	jr iw_done
iw_d012:
	ld a,c
	ld (RV_CMP),a
	jr iw_done
iw_d019:
	ld a,c
	cpl
	ld b,a
	ld a,(RV_IRR)
	and b
	and $0F
	ld (RV_IRR),a
	call vic_irq_line
	jr iw_done
iw_d01a:
	ld a,c
	and $0F
	ld (RV_IMR),a
	call vic_irq_line
	jr iw_done
iw_cia1:
	ld a,l
	and $0F
	cp 4
	jr z,iw_ta_lo
	cp 5
	jr z,iw_ta_hi
	cp $0D
	jr z,iw_icr
	cp $0E
	jp z,iw_cra
	jp iw_done
iw_ta_lo:
	ld a,c
	ld (RV_TLAT),a
	call tlat_lines
	jp iw_done
iw_ta_hi:
	ld a,c
	ld (RV_TLAT+1),a
	call tlat_lines
	ld a,(RV_CRA)
	and 1
	jp nz,iw_done
	ld hl,(RV_TLATL)	; timer stopped: load counter
	ld (RV_TCNT),hl
	jp iw_done
iw_icr:
	ld a,c
	and $1F
	ld b,a
	ld a,(RV_MASK)
	bit 7,c
	jr z,iw_icr_clr
	or b
	jr iw_icr_set
iw_icr_clr:
	ld c,a
	ld a,b
	cpl
	and c
iw_icr_set:
	ld (RV_MASK),a
	jp iw_done
iw_cra:
	ld a,c
	and $EF
	ld (RV_CRA),a
	bit 4,c
	jp z,iw_done
	ld hl,(RV_TLATL)
	ld (RV_TCNT),hl
	jp iw_done

; timer helpers.  The CIA timer runs in raster lines (CYC_LINE cycles each).
tlat_lines:			; RV_TLATL = max(1, RV_TLAT / 63).  Keeps BC, DE.
	ld hl,(RV_TLAT)
	call div63
	ld a,h
	or l
	jr nz,tl_ok
	inc hl
tl_ok:
	ld (RV_TLATL),hl
	ret
div63:				; HL = HL / 63.  Keeps BC, DE.
	push bc
	push de
	ld de,0
	ld bc,63
d63_loop:
	or a
	sbc hl,bc
	jr c,d63_end
	inc de
	jr d63_loop
d63_end:
	ex de,hl
	pop de
	pop bc
	ret
tcnt_cycles:			; HL = RV_TCNT * 63.  Keeps BC, DE.
	push de
	ld hl,(RV_TCNT)
	ld d,h
	ld e,l
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	or a
	sbc hl,de
	pop de
	ret

; VIC IRQ line: IRR bit 7 = (IRR & IMR) != 0.  Keeps BC,DE,HL.
vic_irq_line:
	push bc
	ld a,(RV_IMR)
	ld b,a
	ld a,(RV_IRR)
	and $0F
	ld c,a
	and b
	ld a,c
	jr z,vil_clr
	or $80
vil_clr:
	ld (RV_IRR),a
	pop bc
	ret

; ---- scheduler: the core jumps here when RV_CNT reaches 0 ------------------
	if TEST
emu_done:			; store the 6502 state and stop
	db $FD,$7D		; ld a,iyl (6502 A)
	ld (RV),a		; -> RV_A in memory for the test reader
	ld a,b
	ld (RV_X),a
	ld a,c
	ld (RV_Y),a
	call getpc
	ld (RV_PC),hl
	call pack_p
	ld (RV_PP),a
	ld a,SEG0
	out (PORT_P2),a
emu_halt:
	jr emu_halt
	else
emu_done:
	call sched_line
	call irq_check
	ld a,SLICE
	ld (RV_CNT),a
	jp core_dispatch

; $02 = "beq to an idle loop" (patched into the game): if the branch is taken,
; fast-forward raster lines until an interrupt is taken (or a frame passed).
h_idle:
	db $DD,$7D		; ld a,ixl (Z source)
	or a
	jr z,hi_taken
	inc de
	jp core_dispatch
hi_taken:
	ld a,(de)
	inc de
	ld l,a
	add a,a
	sbc a,a
	ld h,a
	add hl,de
	ex de,hl
	ld a,(RV_P)
	and 4
	jr nz,hi_out		; IRQs off: nothing can end the wait
	ld a,4			; at most 4 events (frame ends) without an IRQ
	ld (RV_T),a
hi_loop:
	push bc
	push de
	call lines_to_event	; HL = lines until something happens
	dec hl
	ld a,h
	or l
	jr z,hi_one
	ex de,hl		; skip DE-1 quiet lines
	ld hl,(RV_LINE)
	add hl,de
	ld (RV_LINE),hl
	ld a,(RV_CRA)
	and 1
	jr z,hi_one
	ld hl,(RV_TCNT)
	or a
	sbc hl,de
	ld (RV_TCNT),hl
hi_one:
	pop de
	pop bc
	call sched_line
	ld a,(RV_ICR)
	ld hl,RV_IRR
	or (hl)
	and $80
	jr nz,hi_irq
	ld hl,RV_T
	dec (hl)
	jr nz,hi_loop
	jr hi_out

; HL = raster lines (>= 1) until the next frame end, raster compare or
; timer underflow.  Uses DE.
lines_to_event:
	ld de,(RV_LINE)
	ld hl,LINES
	or a
	sbc hl,de		; to frame end
	push hl
	ld hl,(RV_CMP)
	or a
	sbc hl,de		; to raster compare
	jr z,lte_wrap
	jr nc,lte_r
lte_wrap:
	ld de,LINES
	add hl,de
lte_r:
	pop de
	call min_hl_de
	ld a,(RV_CRA)
	and 1
	ret z
	ld de,(RV_TCNT)
min_hl_de:			; HL = min(HL, DE)
	push hl
	or a
	sbc hl,de
	pop hl
	ret c
	ex de,hl
	ret

hi_irq:
	call irq_check
hi_out:
	ld a,SLICE
	ld (RV_CNT),a
	jp core_dispatch

; $12 = native version of the game's 8x8 multiply at $687E (patched in):
; X*Y -> X (low), Y (high), with the routine's side effects: $45 = 0,
; $46/$47 = Y << k (k = loop count), A = 0, Z set, C = last bit out.
; shortcut: V is left unchanged (the 6502 loop's adc leaves it undefined-ish).
h_mul:
	push de
	ld e,c
	ld d,0
	ld hl,0
hm_loop:
	srl b
	jr nc,hm_skip
	add hl,de
hm_skip:
	sla e
	rl d
	ld a,0
	adc a,a
	ld (RV_T),a
	inc b
	dec b
	jr nz,hm_loop
	ld ($0046),de
	xor a
	ld ($0045),a
	db $FD,$6F		; ld iyl,a (6502 A)
	db $DD,$67		; ld ixh,a (N source)
	db $DD,$6F		; ld ixl,a (Z source)
	ld a,(RV_T)
	neg
	ld (RV_C),a
	ld b,l
	ld c,h
	pop de
	call kt_rts		; RTS
	jp core_dispatch

; $32 = native version of the music player's SID update at $B00B:
;   ldx #$18 / loop: lda $B70C,x / sta $D400,x / dex / bpl loop  (then rts at $B016)
; Copies the 25 bytes into the SID shadow (gate tracking) or into RAM when
; I/O is not mapped; leaves X = $FF, A = $B70C, N set, Z clear.
SIDBUF:		equ $C6F0		; 25 bytes
h_sidcopy:
	push bc
	ld a,SEG0+2		; $B70C is in segment 6 (window address = 6502 address)
	out (PORT_P2),a
	ld hl,$B70C
	ld de,SIDBUF
	ld bc,25
	ldir
	call port_io
	jr nz,hsc_io
	ld a,SEG0+3		; RAM under I/O: $D400 -> window $9400
	out (PORT_P2),a
	ld hl,SIDBUF
	ld de,$9400
	ld bc,25
	ldir
	jr hsc_done
hsc_io:
	ld a,SEG_IO
	out (PORT_P2),a
	ld de,SIDBUF
	ld hl,$8400		; SID shadow
hsc_loop:
	ld a,(de)
	ld c,a			; new
	ld a,l
	cp 4
	jr z,hsc_gate
	cp 11
	jr z,hsc_gate
	cp 18
	jr nz,hsc_st
hsc_gate:
	ld b,(hl)		; old
	call sid_gate
hsc_st:
	ld (hl),c
	inc hl
	inc de
	ld a,l
	cp 25
	jr nz,hsc_loop
hsc_done:
	pop bc
	ld b,$FF		; X
	ld a,(SIDBUF)
	db $FD,$6F		; ld iyl,a (A)
	ld a,$FF
	db $DD,$67		; ld ixh,a (N)
	db $DD,$6F		; ld ixl,a (Z clear)
	ld hl,$B016
	call setpc
	jp core_dispatch

; $42 = native version of the IRQ's sprite register update at $5690-$56F6
; (patched in; ends with the routine's rts).  For sprite y = 0..7, table
; index x = (x0 + y) & 7 with x0 = ($02A8 & 4) ^ 4:
;   $D027+y = $0250,x   $C3F8+y = $0258,x   $0218,x &= $FD
;   $D000+2y = $0240,x  $D001+2y = $0248,x
;   bits of $0250,x: 7 -> $16 (X expand), 6 -> $17 (Y expand), 5 -> $18 (MC),
;   4 -> $19 (X MSB); $0248,x >= 1 -> $1A (enable)
; then $D01D=$16, $D017=$17, $D01C=$18, $D015=$1A, $D010=$19.
; Exit: A = $19, X = x0, Y = 8, C set, N/Z from A.
h_sprregs:
	push de
	ld a,($02A8)
	and 4
	xor 4
	ld (RV_T),a		; x0
	; VIC registers go to the I/O shadow, or to RAM when I/O is not mapped
	call port_io
	ld a,SEG_IO
	ld d,$80
	jr nz,hsr_seg
	ld a,SEG0+3
	ld d,$90
hsr_seg:
	out (PORT_P2),a
	ld c,0			; y
hsr_loop:
	ld a,(RV_T)
	add a,c
	and 7
	add a,$18
	ld l,a
	ld h,$02		; $0218 + x
	ld a,(hl)
	and $FD
	ld (hl),a
	ld a,(RV_T)
	add a,c
	and 7
	or $50
	ld l,a			; $0250 + x: colour/flags
	ld a,(hl)
	ld b,a
	ld e,c			; VIC $D027+y
	ld a,$27
	add a,e
	ld e,a
	ld a,b
	ld (de),a
	rla			; bit 7 -> $16
	ld hl,$0016
	rr (hl)
	rla			; bit 6 -> $17
	inc l
	rr (hl)
	rla			; bit 5 -> $18
	inc l
	rr (hl)
	rla			; bit 4 -> $19
	inc l
	rr (hl)
	ld a,(RV_T)
	add a,c
	and 7
	or $40
	ld l,a
	ld h,$02		; $0240 + x: X
	ld a,c
	add a,a
	ld e,a			; VIC $D000+2y
	ld a,(hl)
	ld (de),a
	set 3,l			; $0248 + x: Y
	inc e
	ld a,(hl)
	ld (de),a
	cp 1			; carry clear if Y >= 1 ... 6502 cmp sets C = (Y >= 1)
	ccf
	ld hl,$001A
	rr (hl)
	inc c
	ld a,c
	cp 8
	jr nz,hsr_loop
	ld e,$1D
	ld a,($0016)
	ld (de),a
	ld e,$17
	ld a,($0017)
	ld (de),a
	ld e,$1C
	ld a,($0018)
	ld (de),a
	ld e,$15
	ld a,($001A)
	ld (de),a
	ld e,$10
	ld a,($0019)
	ld (de),a
	; sprite pointers $C3F8+y in RAM (segment 7, window $83F8)
	ld a,SEG0+3
	out (PORT_P2),a
	ld c,0
hsr_ptr:
	ld a,(RV_T)
	add a,c
	and 7
	or $58
	ld l,a
	ld h,$02		; $0258 + x
	ld a,(hl)
	ld hl,$83F8
	ld b,0
	add hl,bc
	ld (hl),a
	inc c
	ld a,c
	cp 8
	jr nz,hsr_ptr
	ld a,(RV_CODESEG)
	out (PORT_P2),a
	pop de
	ld a,(RV_T)
	ld b,a			; X = x0
	ld c,8			; Y
	ld a,$FF
	ld (RV_C),a
	ld a,($0019)
	db $FD,$6F		; ld iyl,a
	db $DD,$67		; ld ixh,a
	db $DD,$6F		; ld ixl,a
	call kt_rts		; rts
	jp core_dispatch

; ---- native sprite builders of the game (patched in) ----------------------
SPRBUF:		equ $02C0		; the game's decompressed sprite frame (63+ bytes)

; $72 = sprite frame decompressor at $7E36 (X = frame number):
;   ($06) = $8000,x | $80C0,x << 8; bytes < $A0 or >= $B0 literal, $A0 = next
;   byte literal, $A1-$AF = n zeros; until 63 bytes.  Exit A=$FF (N), C set,
;   X/Y = final buffer / source index, $4E as the 6502 code leaves it.
h_unpack:
	push de
	ld h,$80		; $8000 + X (segment 6)
	ld l,b
	call rd_any
	ld ($0006),a
	ld e,a
	ld a,b			; $80C0 + X (may cross into $81xx)
	add a,$C0
	ld l,a
	ld a,$80
	adc a,0
	ld h,a
	call rd_any
	ld ($0007),a
	ld d,a			; DE = source pointer
	ld b,0			; X
	ld c,0			; Y
hu_loop:
	ld h,0			; source byte (DE + Y)
	ld l,c
	add hl,de
	call rd_any
	ld hl,SPRBUF
	call hu_put
	cp $A0
	jr c,hu_lit
	jr z,hu_esc
	cp $B0
	jr nc,hu_lit
	and $0F			; $A1-$AF: n zeros
	jr hu_zeros
hu_esc:
	inc c			; next byte literal
	ld h,0
	ld l,c
	add hl,de
	call rd_any
	ld hl,SPRBUF
	call hu_put
hu_lit:
	inc b
hu_next:
	inc c
	ld a,b
	cp $3F
	jr c,hu_loop
	pop de
	ld a,$FF
	db $FD,$6F		; ld iyl,a
	db $DD,$67		; ld ixh,a
	db $DD,$6F		; ld ixl,a
	ld (RV_C),a		; C set (cpx #$3F with X >= $3F)
	call kt_rts
	jp core_dispatch
hu_zeros:			; A = n (1-15): n zeros at SPRBUF + X
	push af
	ld a,c
	ld ($004E),a		; sty $4E
	pop af
hu_z1:
	push af
	xor a
	ld hl,SPRBUF
	call hu_put
	inc b
	pop af
	dec a
	jr nz,hu_z1
	jr hu_next
hu_put:				; (SPRBUF + B) = A, page 2 of the 6502 ($02C0..$03BF)
	push hl
	push af
	ld a,l
	add a,b
	ld l,a
	jr nc,hp_nc
	inc h
hp_nc:
	pop af
	ld (hl),a
	pop hl
	ret

; $52 = sprite mask at $7B69: dest = ($04); for y = 62..0:
;   dest[y] = SPRBUF[y] & {$42, $43, $44}[y mod 3].  Exit Y=$FF (N), A = last.
h_mask:
	push de
	ld hl,($0004)
	ld de,SPRBUF
	ld c,21
hmk_row:
	ld a,(de)
	push hl
	ld hl,$0042
	and (hl)
	pop hl
	call wr_ram
	inc de
	inc hl
	ld a,(de)
	push hl
	ld hl,$0043
	and (hl)
	pop hl
	call wr_ram
	inc de
	inc hl
	ld a,(de)
	push hl
	ld hl,$0044
	and (hl)
	pop hl
	call wr_ram
	inc de
	inc hl
	dec c
	jr nz,hmk_row
	ld a,(SPRBUF)		; A = last stored (y = 0)
	ld hl,$0042
	and (hl)
	pop de
	ld c,$FF		; Y
	db $FD,$6F		; ld iyl,a
	ld a,$FF
	db $DD,$67		; ld ixh,a (N from dey)
	db $DD,$6F		; ld ixl,a (Z clear)
	call kt_rts
	jp core_dispatch

; $62 = mirrored sprite mask at $7B86 (T = table at $9D00): for each row r:
;   dest[3r+2] = T[buf[3r]] & $44, dest[3r+1] = T[buf[3r+1]] & $43,
;   dest[3r] = T[buf[3r+2]] & $42.  Exit Y=$FF (N), X = buf[2], A = last.
h_maskflip:
	push de
	ld hl,($0004)
	ld de,SPRBUF
	ld c,21
hmf_row:
	ld a,(de)		; buf[3r] -> dest[3r+2]
	call hmf_t
	push hl
	ld hl,$0044
	and (hl)
	pop hl
	inc hl
	inc hl
	call wr_ram
	dec hl
	inc de
	ld a,(de)		; buf[3r+1] -> dest[3r+1]
	call hmf_t
	push hl
	ld hl,$0043
	and (hl)
	pop hl
	call wr_ram
	dec hl
	inc de
	ld a,(de)		; buf[3r+2] -> dest[3r]
	call hmf_t
	push hl
	ld hl,$0042
	and (hl)
	pop hl
	call wr_ram
	inc hl
	inc hl
	inc hl
	inc de
	dec c
	jr nz,hmf_row
	ld a,(SPRBUF+2)
	ld b,a			; X = buf[2]
	call hmf_t
	ld hl,$0042
	and (hl)
	pop de
	ld c,$FF
	db $FD,$6F		; ld iyl,a
	ld a,$FF
	db $DD,$67
	db $DD,$6F
	call kt_rts
	jp core_dispatch
hmf_t:				; A = T[A] (6502 $9D00 + A).  Keeps BC, DE, HL.
	push hl
	ld l,a
	ld h,$9D
	call rd_any
	pop hl
	ret

; $82 = one iteration of the screen-transition dissolve loop at $7DBB
; (6502 code from $7DB3; loop counter $1E/$1F, RNG at $79D2, masks $7DFC,
; row table $73CD).  Then PC = $7DBB again (or the rts at $7DFB when done)
; and emulated time advances by the 6502 loop's cost, ~207 cycles = 3.3
; raster lines, so the effect keeps its C64 duration and IRQs still run.
DISS_PC:	equ $7DBB
; segment 5 ($4000-$7FFF) holds the code, row table, masks and the RNG's data
; ($5400-$7EFF); the bitmap ($E000-$FFFF) is segment 7.
W5:		equ $8000-$4000		; 6502 address + W5 = window address (seg 5)
W7:		equ $8000-$C000		; 6502 address + W7 = window address (seg 7)
h_dissolve:
	ld a,SEG0+1
	out (PORT_P2),a
hd_r1:
	call rng_fast		; A = random
	ld c,a			; Y
	and 3
	ld b,a			; X = A & 3
	ld a,c
	srl a
	and $3E
	cp $24
	jr nc,hd_r1
	ld l,a			; ($02) = word at $73CD + A
	ld h,0
	ld de,$73CD+W5
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld ($0002),de
hd_r2:
	call rng_fast
	cp $F0
	jr nc,hd_r2
	and $FE
	ld c,a			; Y
	ld a,b			; mask at $7DFC + X
	add a,($7DFC+W5) & 255
	ld l,a
	ld h,($7DFC+W5) / 256
	ld a,(hl)
	ld l,c			; HL = row base + Y (always $E000-$FFFE: segment 7)
	ld h,0
	add hl,de
	push af
	ld a,h			; dirty page flags (screen rows, sprite data)
	sub $C0
	push hl
	ld l,a
	ld h,DIRTY/256
	ld (hl),1
	set 6,l
	ld (hl),1
	pop hl
	ld de,W7
	add hl,de
	ld a,SEG0+3
	out (PORT_P2),a
	pop af
	ld e,a
	ld a,(hl)
	and e
	ld (hl),a
	inc hl
	ld a,(hl)
	and e
	ld (hl),a
	inc c			; Y after iny
	ld a,($001E)		; loop counter
	or a
	jr nz,hd_dec
	ld hl,$001F
	dec (hl)
	jr z,hd_done
hd_dec:
	ld hl,$001E
	dec (hl)
	ld hl,DISS_PC
	call setpc
	jr hd_time
hd_done:
	xor a			; exit like the 6502 code: A = $1E = 0, Z, C clear
	db $FD,$6F		; ld iyl,a
	db $DD,$67		; ld ixh,a
	db $DD,$6F		; ld ixl,a
	ld (RV_C),a
	ld hl,$7DFB		; rts
	call setpc
hd_time:			; advance (33 + carry) / 10 raster lines
	ld a,(RV_DACC)
	add a,33
	ld l,0
hd_t1:
	cp 10
	jr c,hd_t2
	sub 10
	inc l
	jr hd_t1
hd_t2:
	ld (RV_DACC),a
	ld a,l
	call adv_lines
	call irq_check
	jp core_dispatch

; advance A (1-15) raster lines: quiet stretches in one jump, sched_line at
; each event.  Keeps BC, DE.
adv_lines:
	ld (RV_T),a
al_loop:
	push bc
	push de
	call lines_to_event	; HL = lines until the next event (>= 1)
	ld a,(RV_T)
	ld e,a
	ld d,0
	call min_hl_de		; HL = min(event, left)
	dec hl			; lines before the one that runs sched_line
	ld a,(RV_T)
	sub l
	ld (RV_T),a
	ld a,h
	or l
	jr z,al_one
	ex de,hl
	ld hl,(RV_LINE)
	add hl,de
	ld (RV_LINE),hl
	ld a,(RV_CRA)
	and 1
	jr z,al_one
	ld hl,(RV_TCNT)
	or a
	sbc hl,de
	ld (RV_TCNT),hl
al_one:
	pop de
	pop bc
	call sched_line
	ld hl,RV_T
	dec (hl)
	jr nz,al_loop
	ret

; the game's RNG at $79D2 (Y preserved) with segment 5 mapped in page 2:
; $74/$75 pointer ($5400-$7EFF), $76 sum, CIA1 timer A -> A.  Keeps BC, DE.
rng_fast:
	ld a,($0075)
	cp $54
	jr c,rf_seed
	cp $7F
	jr c,rf_go
rf_seed:
	call tcnt_cycles	; timer A: L = $DC04, H = $DC05
	ld a,l
	and $1F
	add a,$54
	ld ($0075),a
	ld a,h
	ld ($0074),a
rf_go:
	push de
	ld hl,($0074)
	ld de,W5
	add hl,de
	ld a,($0076)
	add a,(hl)		; adc ($74),y with C = 0
	push af
	call tcnt_cycles
	pop af
	adc a,l			; adc $DC04 (carry from the first add)
	ld ($0076),a
	ld hl,($0074)
	inc hl
	ld ($0074),hl
	pop de
	ret

; advance one raster line: render at frame end, raster compare, CIA timer.
; Keeps BC, DE; re-maps the code segment.
sched_line:
	push bc
	push de
	push ix			; (IX/IY hold 6502 flags/A; render and sound use IX)
	push iy
	ld hl,(RV_LINE)
	inc hl
	ld bc,LINES
	or a
	sbc hl,bc
	jr nz,sc_noframe
	ld hl,(RV_FRAMES)
	inc hl
	ld (RV_FRAMES),hl
	if STOPFRAME
	push de
	ld de,STOPFRAME
	or a
	sbc hl,de
	add hl,de
	pop de
	jr nz,sc_nostop
sc_stop:
	jr sc_stop		; check build: freeze the machine at frame STOPFRAME
sc_nostop:
	endif
	ld a,l
	and RENDER_EVERY-1
	call z,render_maybe
	call sound_update
	if THROTTLE
	call frame_sync
	endif
	ld hl,0
	jr sc_line
sc_noframe:
	add hl,bc
sc_line:
	ld (RV_LINE),hl
	ld bc,(RV_CMP)
	or a
	sbc hl,bc
	jr nz,sc_nocmp
	ld a,(RV_IRR)
	or 1
	ld (RV_IRR),a
	call vic_irq_line
sc_nocmp:
	ld a,(RV_CRA)
	and 1
	jr z,sc_notimer
	ld hl,(RV_TCNT)
	dec hl
	ld a,h
	or l
	jr nz,sc_tset
	ld hl,(RV_TLATL)
	ld a,(RV_MASK)
	and 1
	ld b,a
	ld a,(RV_ICR)
	or 1
	bit 0,b
	jr z,sc_tflag
	or $80
sc_tflag:
	ld (RV_ICR),a
sc_tset:
	ld (RV_TCNT),hl
sc_notimer:
	ld a,(RV_CODESEG)
	out (PORT_P2),a
	pop iy
	pop ix
	pop de
	pop bc
	ret

; wait for the next 20 ms frame slot on the turbo R system timer ($E6/$E7).
; More than 2 frames late: resynchronise instead of catching up.
frame_sync:
	call sys_timer
	ld de,(RV_DEADLINE)
	or a
	sbc hl,de		; d = now - deadline (16 bit, wraps every 256 ms)
	ld bc,2*TICKS_FRAME
	add hl,bc		; d + 2 frames < 2 frames: up to 2 frames early -> wait
	or a
	sbc hl,bc
	jr nc,fs_late		; (carry: d + 2F < 2F unsigned)
fs_wait:
	call sys_timer
	or a
	sbc hl,de
	bit 7,h
	jr nz,fs_wait
	jr fs_next
fs_late:			; HL = d + 2F - 2F... recompute d
	call sys_timer
	or a
	sbc hl,de
	ld bc,2*TICKS_FRAME
	or a
	sbc hl,bc
	jr c,fs_next		; less than 2 frames late: keep the schedule
	ld hl,(RV_LATE)
	inc hl
	ld (RV_LATE),hl
	call sys_timer
	ex de,hl		; resync: deadline = now
fs_next:
	ld hl,TICKS_FRAME
	add hl,de
	ld (RV_DEADLINE),hl
	ret
sys_timer:			; HL = system timer (consistent read)
	in a,($E7)
	ld h,a
	in a,($E6)
	ld l,a
	in a,($E7)
	cp h
	ret z
	jr sys_timer

; skip the render while behind the 50 Hz schedule (at most 3 in a row), so
; the game code, and with it the IRQ-driven music, keeps real-time speed.
render_maybe:
	if THROTTLE
	ld a,(RV_SKIP)
	cp 3
	jr nc,rm_draw
	call sys_timer
	ld de,(RV_DEADLINE)
	or a
	sbc hl,de		; now - deadline
	bit 7,h
	jr nz,rm_draw		; on time
	ld a,h			; ignore huge values (deadline not set yet / wrap)
	cp $40
	jr nc,rm_draw
	ld hl,RV_SKIP
	inc (hl)
	ld hl,(RV_NSKIP)
	inc hl
	ld (RV_NSKIP),hl
	ret
rm_draw:
	xor a
	ld (RV_SKIP),a
	endif
render_timed:			; render, adding its duration to RV_RTICKS
	call sys_timer
	push hl
	call render
	call sys_timer
	pop de
	or a
	sbc hl,de
	ld de,(RV_RTICKS)
	add hl,de
	ld (RV_RTICKS),hl
	ret

; take the IRQ if one is pending and I is clear
irq_check:
	ld a,(RV_P)
	and 4
	ret nz
	ld a,(RV_IRR)
	ld l,a
	ld a,(RV_ICR)
	or l
	and $80
	ret z
	jp take_irq

; push PC and P, set I, vector through $FFFE or the KERNAL ($0314)
take_irq:
	ld hl,(RV_NIRQ)
	inc hl
	ld (RV_NIRQ),hl
	call getpc
	ex de,hl
	ld hl,(RV_S)
	ld (hl),d
	dec l
	ld (hl),e
	dec l
	ld (RV_S),hl
	call pack_p
	or $20
	ld hl,(RV_S)
	ld (hl),a
	dec l
	ld (RV_S),hl
	ld hl,RV_P
	set 2,(hl)
	call port_kern
	jr z,ti_hw
	ld hl,(RV_S)		; KERNAL $FF48: pha / txa / pha / tya / pha
	db $FD,$7D		; ld a,iyl (6502 A)
	ld (hl),a
	dec l
	ld (hl),b
	dec l
	ld (hl),c
	dec l
	ld (RV_S),hl
	ld hl,$0314
	jr ti_vec
ti_hw:
	ld hl,$FFFE
ti_vec:
	call rd_any
	push af
	inc l
	call rd_any
	ld h,a
	pop af
	ld l,a
	jp setpc
	endif

core_dispatch:
	ld a,(de)
	inc de
	ld l,a
	ld h,optab_lo/256
	ld a,(hl)
	inc h
	ld h,(hl)
	ld l,a
	jp (hl)

emu_bad:			; illegal opcode: stop (PC in DE)
	jr emu_bad

	include "video.asm"
	include "kernal.asm"
	include "sound.asm"
	include "core.asm"
