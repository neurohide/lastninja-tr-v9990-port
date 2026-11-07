; V9990 output and MSX input for the Last Ninja emulator.
; Screen: B3 (512 px wide, 4 bpp), palette entries 0-15 = C64 colours.
; A C64 multicolour pixel becomes 3 V9990 pixels (160 -> 480 px).
; Only multicolour bitmap mode is drawn (what the game uses in play);
; sprites are not drawn yet.

V_VRAM:		equ $60
V_PAL:		equ $61
V_REG:		equ $63
V_SEL:		equ $64
V_SYS:		equ $67
VID_X:		equ 8			; byte offset of C64 column 0 (16 px)
VID_Y:		equ 6			; V9990 line of C64 bitmap line 0
CELLTAB:	equ $C300		; 40 cells x 4 colours (byte = c*17), page aligned
ROWBUF:		equ $C200		; 40 colour RAM + 40 screen bytes

v_init:
	ld a,2
	out (V_SYS),a
	xor a
	out (V_SYS),a
	ld hl,v_regs
vi_loop:
	ld a,(hl)
	cp $FF
	jr z,vi_pal
	inc hl
	out (V_SEL),a
	ld a,(hl)
	inc hl
	out (V_REG),a
	jr vi_loop
vi_pal:
	ld a,14
	out (V_SEL),a
	xor a
	out (V_REG),a
	ld hl,c64_rgb
	ld b,16*3
vi_pal2:
	ld a,(hl)
	out (V_PAL),a
	inc hl
	djnz vi_pal2
	; clear 512K VRAM
	xor a
	out (V_SEL),a
	out (V_REG),a
	out (V_REG),a
	out (V_REG),a
	ld de,2048
vi_clr:
	ld b,0
	xor a
vi_clr2:
	out (V_VRAM),a
	djnz vi_clr2
	dec de
	ld a,d
	or e
	jr nz,vi_clr
	ret
v_regs:
	db 6, $95		; B3: bitmap, 512 px, 4 bpp
	db 7, $08		; PAL, non interlaced
	db 8, $C2		; display on
	db 9, $00		; no V9990 interrupts
	db 13, $00		; palette offset 0
	db 15, 0		; backdrop
	db 16, $00
	db 17, 0, 18, 0, 19, 0, 20, 0
	db 25, 0, 26, 0, 27, 0, 28, 0
	db $FF

; C64 colours (Pepto) as V9990 5-bit R,G,B (from buggyboymsx)
c64_rgb:
	db  0, 0, 0,  31,31,31,  21, 7,11,  15,30,26
	db 21, 8,30,  12,26, 6,   5, 7,29,  31,31, 8
	db 24,13, 3,  15,10, 0,  30,16,16,  12,12,12
	db 18,18,18,  20,31,16,  14,16,31,  25,25,25

; ---- draw the multicolour bitmap: screen $C000, bitmap $E000 (VIC bank 3) --
; shortcut: fixed addresses (what the game sets: $DD00=$94, $D018=$08);
; read $DD00/$D018 when other screens (title, map) need drawing.
render:
	push de
	; border colour -> backdrop
	ld a,SEG_IO
	out (PORT_P2),a
	ld a,($8020)
	and $0F
	ld b,a
	ld a,15
	out (V_SEL),a
	ld a,b
	out (V_REG),a
	ld a,($8021)
	and $0F
	ld (rd_bg),a
	ld hl,rd_lastbg		; background changed: redraw everything
	cp (hl)
	ld (hl),a
	call nz,dirty_all
	xor a
	ld (rd_row),a
rd_rowloop:
	; colour RAM row -> ROWBUF, screen row -> ROWBUF+40
	ld a,(rd_row)
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl		; row*8
	ld d,h
	ld e,l
	add hl,hl
	add hl,hl		; row*32
	add hl,de		; row*40
	ld (rd_r40),hl
	call row_dirty
	jp z,rd_nextrow
	ld hl,(rd_r40)
	ld a,SEG_IO
	out (PORT_P2),a
	ld de,$8800		; $D800 in SEG_IO
	add hl,de
	ld de,ROWBUF
	ld bc,40
	ldir
	ld a,SEG0+3
	out (PORT_P2),a
	ld hl,(rd_r40)
	ld de,$8000		; $C000 in SEG0+3
	add hl,de
	ld de,ROWBUF+40
	ld bc,40
	ldir
	; cell colour tables
	ld ix,ROWBUF
	ld hl,CELLTAB
	ld b,40
rd_cells:
	ld a,(rd_bg)
	call x17
	ld (hl),a
	inc hl
	ld a,(ix+40)
	rrca
	rrca
	rrca
	rrca
	and $0F
	call x17
	ld (hl),a
	inc hl
	ld a,(ix+40)
	and $0F
	call x17
	ld (hl),a
	inc hl
	ld a,(ix+0)
	and $0F
	call x17
	ld (hl),a
	inc hl
	inc ix
	djnz rd_cells
	; bitmap row base: $A000 + row*320 (SEG0+3 holds $C000-$FFFF)
	ld hl,(rd_r40)
	add hl,hl
	add hl,hl
	add hl,hl		; row*320
	ld de,$A000
	add hl,de
	ld (rd_bm),hl
	xor a
	ld (rd_line),a
rd_lineloop:
	; VRAM address = (row*8 + line + VID_Y) * 256 + VID_X
	ld a,(rd_row)
	add a,a
	add a,a
	add a,a
	ld b,a
	ld a,(rd_line)
	add a,b
	add a,VID_Y
	ld b,a
	xor a
	out (V_SEL),a
	ld a,VID_X
	out (V_REG),a
	ld a,b
	out (V_REG),a
	xor a
	out (V_REG),a
	ld a,(rd_line)
	ld e,a
	ld d,0
	ld ix,(rd_bm)
	add ix,de
	ld h,CELLTAB/256
	ld b,0			; col*4
	ld de,8
rd_byte:
	ld a,(ix+0)
	ld c,a
	rlca
	rlca
	and 3
	or b
	ld l,a
	ld a,(hl)
	out (V_VRAM),a
	and $F0
	ld d,a
	ld a,c
	rrca
	rrca
	rrca
	rrca
	and 3
	or b
	ld l,a
	ld a,(hl)
	ld e,a
	and $0F
	or d
	out (V_VRAM),a
	ld a,e
	out (V_VRAM),a
	ld a,c
	rrca
	rrca
	and 3
	or b
	ld l,a
	ld a,(hl)
	out (V_VRAM),a
	and $F0
	ld d,a
	ld a,c
	and 3
	or b
	ld l,a
	ld a,(hl)
	ld e,a
	and $0F
	or d
	out (V_VRAM),a
	ld a,e
	out (V_VRAM),a
	ld de,8
	add ix,de
	ld a,b
	add a,4
	ld b,a
	cp 160
	jr nz,rd_byte
	ld a,(rd_line)
	inc a
	ld (rd_line),a
	cp 8
	jp nz,rd_lineloop
rd_nextrow:
	ld a,(rd_row)
	inc a
	ld (rd_row),a
	cp 25
	jp nz,rd_rowloop
	ld hl,DIRTY		; all drawn
	ld b,64
rd_clr:
	ld (hl),0
	inc hl
	djnz rd_clr
	pop de
	ret

dirty_all:
	ld hl,DIRTY
	ld b,64
da_loop:
	ld (hl),1
	inc hl
	djnz da_loop
	ret

; NZ if any page holding row data changed: HL = row*40.
; screen ($C000) and colour RAM ($D800): pages of row*40 and row*40+39;
; bitmap ($E000): pages of row*320 .. row*320+319.
row_dirty:
	push hl
	ld de,39
	add hl,de
	ld e,h			; last screen page
	pop hl
	push hl
	ld d,h			; first screen page
	ld h,DIRTY/256
	ld l,d
	ld b,(hl)
	ld l,e
	ld a,(hl)
	or b
	ld b,a
	ld a,d
	add a,$18		; colour RAM
	ld l,a
	ld a,(hl)
	or b
	ld b,a
	ld a,e
	add a,$18
	ld l,a
	ld a,(hl)
	or b
	ld b,a
	pop hl
	add hl,hl
	add hl,hl
	add hl,hl		; row*320
	ld a,h
	push hl
	ld de,319
	add hl,de
	ld e,h			; last bitmap page
	pop hl
	ld d,a			; first bitmap page
	ld h,DIRTY/256
rdy_loop:
	ld a,d
	add a,$20		; bitmap at $E000
	ld l,a
	ld a,(hl)
	or b
	ld b,a
	ld a,d
	inc d
	cp e
	jr nz,rdy_loop
	ld a,b
	or a
	ret

x17:				; A = colour 0-15 -> colour * $11
	push bc
	ld c,a
	rlca
	rlca
	rlca
	rlca
	or c
	pop bc
	ret

; ---- C64 joystick port 2 from MSX joystick 1 + cursor keys/space ----------
; out: A = C64 $DC00 bits, active low: b0 up b1 down b2 left b3 right b4 fire
joy_read:
	push bc
	ld a,15
	out ($A0),a
	in a,($A2)
	and $BF
	out ($A1),a
	ld a,14
	out ($A0),a
	in a,($A2)
	or $E0			; MSX: b0 up b1 down b2 left b3 right b4 trig A
	ld b,a
	in a,($AA)		; keyboard row 8: b0 space b4 left b5 up b6 down b7 right
	and $F0
	or 8
	out ($AA),a
	in a,($A9)
	ld c,a
	bit 5,c
	jr nz,jr1
	res 0,b
jr1:	bit 6,c
	jr nz,jr2
	res 1,b
jr2:	bit 4,c
	jr nz,jr3
	res 2,b
jr3:	bit 7,c
	jr nz,jr4
	res 3,b
jr4:	bit 0,c
	jr nz,jr5
	res 4,b
jr5:	ld a,b
	pop bc
	ret
