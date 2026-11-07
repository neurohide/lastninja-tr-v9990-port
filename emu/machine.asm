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
SLICE:		equ 4
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
	ei
	call BDOS
	di
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
	ld (RV_A),a
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
	ld a,(RV_KERN)
	or a
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
	ld a,(RV_IO)
	or a
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

wr_hi:
	ld (RV_T),a
	if TRAPS
	ld a,h
	cp $D0
	jr c,wh_ram
	cp $E0
	jr nc,wh_ram
	ld a,(RV_IO)
	or a
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
	ld a,(RV_N)
	and $80
	or l
	ld l,a
	ld a,(RV_V)
	or a
	jr z,pp_v
	set 6,l
pp_v:
	ld a,(RV_Z)
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
	ld (RV_N),a
	ld a,l
	and 2
	xor 2
	ld (RV_Z),a
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
	ld a,h
	cp $D4
	jr nc,iw_notvic
	ld a,l
	and $3F
	ld l,a
	ld h,$D0
iw_notvic:
	push hl
	ld a,h
	cp $D8
	jr c,iw_nod
	cp $DC
	jr nc,iw_nod
	sub $C0			; colour RAM page -> dirty flags $18-$1B
	ld l,a
	ld h,DIRTY/256
	ld (hl),1
	pop hl
	push hl
iw_nod:
	call io_map
	ld (hl),c
	pop hl
	ld a,h
	cp $D0
	jr z,iw_vic
	cp $DC
	jr z,iw_cia1
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
	ld a,(RV_Z)
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

; advance one raster line: render at frame end, raster compare, CIA timer.
; Keeps BC, DE; re-maps the code segment.
sched_line:
	push bc
	push de
	ld hl,(RV_LINE)
	inc hl
	ld bc,LINES
	or a
	sbc hl,bc
	jr nz,sc_noframe
	ld hl,(RV_FRAMES)
	inc hl
	ld (RV_FRAMES),hl
	ld a,l
	and RENDER_EVERY-1
	call z,render
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
	pop de
	pop bc
	ret

; wait for the next 20 ms frame slot on the turbo R system timer ($E6/$E7).
; More than 2 frames late: resynchronise instead of catching up.
frame_sync:
	call sys_timer
	ld de,(RV_DEADLINE)
	or a
	sbc hl,de		; now - deadline
	bit 7,h
	jr z,fs_late_chk	; already past the deadline
fs_wait:
	call sys_timer
	or a
	sbc hl,de
	bit 7,h
	jr nz,fs_wait
	jr fs_next
fs_late_chk:
	ld bc,2*TICKS_FRAME
	or a
	sbc hl,bc
	jr c,fs_next
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
	ld a,(RV_KERN)
	or a
	jr z,ti_hw
	ld hl,(RV_S)		; KERNAL $FF48: pha / txa / pha / tya / pha
	ld a,(RV_A)
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
	include "core.asm"
