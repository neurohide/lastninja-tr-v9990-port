; Test ROM: runs the generated 6502 core on a program from testdata.inc
SEG0:		equ 4
TRAPS:		equ 0
PORT_P2:	equ $FE
RV:		equ $C000
RV_A:		equ RV
RV_X:		equ RV+1
RV_Y:		equ RV+2
RV_S:		equ RV+3
RV_P:		equ RV+4
RV_T:		equ RV+5
RV_CNT:		equ RV+6
RV_PC:		equ RV+8
	org $4000
	db "AB"
	dw init
	dw 0, 0, 0
	defs 6,0
init:
	di
	ld sp,$F000
	xor a
	ld (RV_T),a
zl:	ld a,(RV_T)
	add a,SEG0
	out (PORT_P2),a
	ld hl,$8000
	ld de,$8001
	ld bc,$3FFF
	ld (hl),0
	ldir
	ld a,(RV_T)
	inc a
	ld (RV_T),a
	cp 4
	jr nz,zl
	ld a,SEG0
	out (PORT_P2),a
	ld hl,prog
	ld de,$8200
	ld bc,progend-prog
	ldir
	ld a,(initregs)
	ld (RV_A),a
	ld a,(initregs+1)
	ld (RV_X),a
	ld a,(initregs+2)
	ld (RV_Y),a
	ld a,(initregs+3)
	ld (RV_P),a
	ld a,$FF
	ld (RV_S),a
	ld hl,(initregs+4)
	ld (RV_CNT),hl
	ld de,$0200
	jp next
emu_done:
	ld (RV_PC),de
	ld a,SEG0
	out (PORT_P2),a
fin:	jr fin
	include "core.asm"
	include "testdata.inc"
