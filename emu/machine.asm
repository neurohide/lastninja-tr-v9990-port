; Last Ninja on MSX turbo R: C64 machine around the generated 6502 core.
; ROM: ASCII16, bank 0 = this code (page 1), banks 1-4 = C64 RAM image,
; bank 5 = C64 I/O page ($D000-$DFFF) captured in VICE.
; 6502 RAM = mapper segments SEG0..SEG0+3, I/O shadow ($D000-$DFFF) = SEG_IO,
; all seen through Z80 page 2.  Timing: one raster line per SLICE instructions.

SEG0:		equ 4
SEG_IO:		equ 8
TRAPS:		equ 1
PORT_P2:	equ $FE
CHGCPU:		equ $0180
ASCII16_P1:	equ $6000
SLICE:		equ 16
LINES:		equ 312
CYC_LINE:	equ 63
	include "state.inc"

RV:		equ $C000
RV_A:		equ RV+0
RV_X:		equ RV+1
RV_Y:		equ RV+2
RV_S:		equ RV+3
RV_P:		equ RV+4
RV_T:		equ RV+5
RV_CNT:		equ RV+6	; 2
RV_PC:		equ RV+8	; 2
RV_IO:		equ RV+10	; 1 = I/O visible at $D000
RV_KERN:	equ RV+11	; 1 = KERNAL visible (IRQ via $0314)
RV_PORT:	equ RV+12	; CPU port $01
RV_LINE:	equ RV+14	; 2 raster line
RV_FRAMES:	equ RV+16	; 2
RV_CMP:		equ RV+18	; 2 raster compare
RV_IRR:		equ RV+20
RV_IMR:		equ RV+21
RV_ICR:		equ RV+22	; CIA1 pending flags (bit7 = IRQ)
RV_MASK:	equ RV+23	; CIA1 interrupt mask
RV_CRA:		equ RV+24
RV_TCNT:	equ RV+26	; 2 CIA1 timer A counter
RV_TLAT:	equ RV+28	; 2 CIA1 timer A latch
RV_NIRQ:	equ RV+30	; 2 IRQs taken (debug)
rd_bg:		equ RV+32
rd_row:		equ RV+33
rd_line:	equ RV+34
rd_r40:		equ RV+36	; 2
rd_bm:		equ RV+38	; 2
COPYRT:		equ $C100

	org $4000
	db "AB"
	dw init
	dw 0, 0, 0
	defs 6,0

init:
	ld a,$81		; R800 ROM mode
	call CHGCPU
	di
	ld sp,$F000
	ld hl,copy_rt
	ld de,COPYRT
	ld bc,copy_end-copy_rt
	ldir
	call COPYRT
	call v_init
	if RENDER_TEST
	call render
rt_halt:	jr rt_halt
	endif
	; machine state
	ld hl,RV
	ld de,RV+1
	ld bc,63
	ld (hl),0
	ldir
	ld a,ST_A
	ld (RV_A),a
	ld a,ST_X
	ld (RV_X),a
	ld a,ST_Y
	ld (RV_Y),a
	ld a,ST_S
	ld (RV_S),a
	ld a,ST_P
	ld (RV_P),a
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
	ld hl,ST_TCNT
	ld (RV_TCNT),hl
	ld a,START_PORT
	ld hl,1
	call wr
	ld hl,SLICE
	ld (RV_CNT),hl
	ld de,START_PC
	jp next

; runs from RAM: page 1 ROM banks 1-4 -> mapper segments SEG0..SEG0+3
copy_rt:
	ld b,0
cr_loop:
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
	cp 5			; 4 RAM segments + I/O shadow (SEG_IO = SEG0+4)
	jr nz,cr_loop
	xor a
	ld (ASCII16_P1),a
	ret
copy_end:

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
	ld a,(RV_TCNT)
	jr ir_done
ir_ta_hi:
	ld a,(RV_TCNT+1)
	jr ir_done

; ---- I/O write: entered by jp with AF pushed; HL = $D000-$DFFF -------------
io_wr:
	pop af
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
	jr z,iw_cra
	jr iw_done
iw_ta_lo:
	ld a,c
	ld (RV_TLAT),a
	jr iw_done
iw_ta_hi:
	ld a,c
	ld (RV_TLAT+1),a
	ld a,(RV_CRA)
	and 1
	jr nz,iw_done
	ld hl,(RV_TLAT)		; timer stopped: load counter
	ld (RV_TCNT),hl
	jr iw_done
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
	ld c,a			; value already stored in shadow
	jp iw_done
iw_cra:
	ld a,c
	and $EF
	ld (RV_CRA),a
	bit 4,c
	jp z,iw_done
	ld hl,(RV_TLAT)
	ld (RV_TCNT),hl
	jp iw_done

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

; ---- scheduler: called by the core every SLICE instructions ---------------
emu_done:
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
	ld bc,CYC_LINE
	or a
	sbc hl,bc
	jr nc,sc_tset
	ld bc,(RV_TLAT)
	add hl,bc
	inc hl
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
	ld a,(RV_P)
	and 4
	jr nz,sc_resume
	ld a,(RV_IRR)
	ld b,a
	ld a,(RV_ICR)
	or b
	and $80
	jr z,sc_resume
	call take_irq
sc_resume:
	ld hl,SLICE
	ld (RV_CNT),hl
	jp next

; push PC and P, set I, vector through $FFFE or the KERNAL ($0314)
take_irq:
	ld hl,(RV_NIRQ)
	inc hl
	ld (RV_NIRQ),hl
	ld a,d
	call push8
	ld a,e
	call push8
	ld a,(RV_P)
	and $EF
	or $20
	call push8
	ld hl,RV_P
	set 2,(hl)
	ld a,(RV_KERN)
	or a
	jr z,ti_hw
	ld a,(RV_A)		; KERNAL $FF48: pha / txa / pha / tya / pha
	call push8
	ld a,(RV_X)
	call push8
	ld a,(RV_Y)
	call push8
	ld hl,$0314
	jr ti_vec
ti_hw:
	ld hl,$FFFE
ti_vec:
	call rd
	ld e,a
	inc hl
	call rd
	ld d,a
	ret

	include "video.asm"
	include "core.asm"
