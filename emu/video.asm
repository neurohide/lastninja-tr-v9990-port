; V9990 output and MSX input for the Last Ninja emulator.
; Screen: B3, 512 px wide, 8 bpp (palette mode), 512 bytes per VRAM line.
;   palette 0-15  = C64 colours (background)
;   palette 16-31 = C64 colours (sprites; 0 stays transparent for the blitter)
; A C64 multicolour pixel becomes 3 V9990 pixels (160 -> 480 px), a hires
; pixel 1.5 (pairs a,b -> a, a|b, b).
; VRAM: display at y 0-211, sprite-free copy of the background at y 256-467.
; Per frame: changed character rows are drawn into the clean copy and blitted
; to the display, old sprite boxes are restored from the clean copy, then the
; sprites are drawn with the blitter's transparent copy.
; Only multicolour bitmap mode is drawn (the in-game screen).

V_VRAM:		equ $60
V_PAL:		equ $61
V_CMD:		equ $62
V_REG:		equ $63
V_SEL:		equ $64
V_STAT:		equ $65
V_SYS:		equ $67
VID_X:		equ 16			; V9990 x of C64 pixel column 0
VID_Y:		equ 6			; V9990 y of C64 bitmap line 0
CLEAN_Y:	equ 256			; y of the sprite-free background copy
CELLTAB:	equ $C300		; 40 cells x 4 colours, page aligned
ROWBUF:		equ $C200		; 40 colour RAM + 40 screen bytes
SPRREG:		equ $C500		; copy of $D000-$D02E
OLDBOX:		equ $C540		; 8 x (x, y, w, h) words: boxes drawn last frame
SPRLINE:	equ $C600		; one decoded sprite line (72 px)
HV:		equ $C660		; 24 hires-resolution pixel values of a line
sp_n:		equ $C680		; sprite number
sp_x:		equ $C682		; 2 V9990 x (signed)
sp_y:		equ $C684		; 2 V9990 y (signed)
sp_w:		equ $C686		; 2 width in V9990 px
sp_h:		equ $C688		; 2 height
sp_data:	equ $C68A		; 2 window address of the sprite data
sp_flags:	equ $C68C		; bit 0 MC, bit 1 X expand, bit 2 Y expand
sp_c:		equ $C68D		; 4 colour lookup: 0, mc0, colour, mc1 (+16)
sp_cx0:		equ $C692		; 2 first visible column
sp_cw:		equ $C694		; 2 visible width
sp_cy0:		equ $C696		; 2 first visible line
sp_ch:		equ $C698		; 2 visible height
sp_row:		equ $C69A		; source row counter
sp_ymul:	equ $C69B		; 1 or 2 (Y expand)
WIN_X0:		equ VID_X
WIN_X1:		equ VID_X+480
WIN_Y0:		equ VID_Y
WIN_Y1:		equ VID_Y+200

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
	ld c,2			; palette 0-15, then the same at 16-31
vi_pal1:
	ld hl,c64_rgb
	ld b,16*3
vi_pal2:
	ld a,(hl)
	out (V_PAL),a
	inc hl
	djnz vi_pal2
	dec c
	jr nz,vi_pal1
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
	ld hl,OLDBOX		; no sprite boxes yet
	ld b,64
vi_ob:
	ld (hl),0
	inc hl
	djnz vi_ob
	ret
v_regs:
	db 6, $96		; B3: bitmap, 512 px, 8 bpp
	db 7, $08		; PAL, non interlaced
	db 8, $C2		; display on
	db 9, $00		; no V9990 interrupts
	db 13, $00		; palette mode
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

; ---- blitter -----------------------------------------------------------------
v_wait:				; wait until the command engine is idle
	in a,(V_STAT)
	rrca
	jr c,v_wait
	ret

; LMMM: copy NX x NY from (SX, SY) to (DX, DY).  Parameters in BLT_*.
BLT:		equ $C6A0		; SX, SY, DX, DY, NX, NY (words)
blit:
	call v_wait
	ld a,32
	out (V_SEL),a
	ld hl,BLT
	ld bc,12*256+V_REG
	otir
	xor a
	out (V_REG),a		; ARG
	ld a,$0C
	out (V_REG),a		; LOP: copy
	ld a,$FF
	out (V_REG),a		; WM
	out (V_REG),a
	xor a
	out (V_REG),a		; FC
	out (V_REG),a
	out (V_REG),a		; BC
	out (V_REG),a
	ld a,$40
	out (V_REG),a		; CMD: LMMM
	ret

; ---- frame update ------------------------------------------------------------
; shortcut: fixed VIC bank 3 layout (what the game sets in play: $DD00=$94,
; $D018=$08 -> screen $C000, bitmap $E000); title/map screens need $DD00/$D018.
render:
	push de
	ld a,SEG_IO
	out (PORT_P2),a
	ld a,($8020)		; border -> backdrop
	and $0F
	ld b,a
	ld a,15
	out (V_SEL),a
	ld a,b
	out (V_REG),a
	ld hl,$8000		; sprite registers for later (SEG_IO is mapped now)
	ld de,SPRREG
	ld bc,$2F
	ldir
	ld a,(SPRREG+$21)
	and $0F
	ld (rd_bg),a
	ld hl,rd_lastbg		; background changed: redraw everything
	cp (hl)
	ld (hl),a
	call nz,dirty_all
	call bg_rows
	call spr_erase
	call spr_draw
	pop de
	ret

; draw changed character rows into the clean copy and blit them on screen
bg_rows:
	xor a
	ld (rd_row),a
rd_rowloop:
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
	ld de,$8800		; colour RAM ($D800 in SEG_IO)
	add hl,de
	ld de,ROWBUF
	ld bc,40
	ldir
	ld a,SEG0+3
	out (PORT_P2),a
	ld hl,(rd_r40)
	ld de,$8000		; screen ($C000 in SEG0+3)
	add hl,de
	ld de,ROWBUF+40
	ld bc,40
	ldir
	; cell colour tables: bg, screen hi, screen lo, colour RAM
	ld ix,ROWBUF
	ld hl,CELLTAB
	ld b,40
rd_cells:
	ld a,(rd_bg)
	ld (hl),a
	inc hl
	ld a,(ix+40)
	rrca
	rrca
	rrca
	rrca
	and $0F
	ld (hl),a
	inc hl
	ld a,(ix+40)
	and $0F
	ld (hl),a
	inc hl
	ld a,(ix+0)
	and $0F
	ld (hl),a
	inc hl
	inc ix
	djnz rd_cells
	ld hl,(rd_r40)
	add hl,hl
	add hl,hl
	add hl,hl		; row*320
	ld de,$A000		; bitmap ($E000 in SEG0+3)
	add hl,de
	ld (rd_bm),hl
	xor a
	ld (rd_line),a
rd_lineloop:
	; VRAM address of (VID_X, CLEAN_Y + VID_Y + row*8 + line), 512 bytes/line
	ld a,(rd_row)
	add a,a
	add a,a
	add a,a
	ld b,a
	ld a,(rd_line)
	add a,b
	add a,VID_Y
	ld l,a
	ld h,CLEAN_Y/256	; HL = y
	xor a
	out (V_SEL),a
	ld a,VID_X
	out (V_REG),a
	ld a,l
	add a,a
	out (V_REG),a		; (y*2) & 255
	ld a,h
	rla			; carry from y*2, plus h*2
	out (V_REG),a
	ld a,(rd_line)
	ld e,a
	ld d,0
	ld ix,(rd_bm)
	add ix,de
	ld h,CELLTAB/256
	ld b,0			; col*4
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
	out (V_VRAM),a
	out (V_VRAM),a
	ld a,c
	rrca
	rrca
	rrca
	rrca
	and 3
	or b
	ld l,a
	ld a,(hl)
	out (V_VRAM),a
	out (V_VRAM),a
	out (V_VRAM),a
	ld a,c
	rrca
	rrca
	and 3
	or b
	ld l,a
	ld a,(hl)
	out (V_VRAM),a
	out (V_VRAM),a
	out (V_VRAM),a
	ld a,c
	and 3
	or b
	ld l,a
	ld a,(hl)
	out (V_VRAM),a
	out (V_VRAM),a
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
	; blit the row from the clean copy to the display
	ld a,(rd_row)
	add a,a
	add a,a
	add a,a
	add a,VID_Y
	ld l,a
	ld h,0
	ld (BLT+6),hl		; DY
	inc h			; + 256 = CLEAN_Y
	ld (BLT+2),hl		; SY
	ld hl,VID_X
	ld (BLT+0),hl		; SX
	ld (BLT+4),hl		; DX
	ld hl,480
	ld (BLT+8),hl		; NX
	ld hl,8
	ld (BLT+10),hl		; NY
	call blit
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

; ---- sprites -----------------------------------------------------------------
; restore last frame's sprite boxes from the clean copy
spr_erase:
	ld ix,OLDBOX
	ld b,8
se_loop:
	push bc
	ld l,(ix+4)
	ld h,(ix+5)		; w = 0: no box
	ld a,h
	or l
	jr z,se_next
	ld (BLT+8),hl
	ld l,(ix+6)
	ld h,(ix+7)
	ld (BLT+10),hl
	ld l,(ix+0)
	ld h,(ix+1)
	ld (BLT+0),hl
	ld (BLT+4),hl
	ld l,(ix+2)
	ld h,(ix+3)
	ld (BLT+6),hl
	inc h
	ld (BLT+2),hl		; clean copy is 256 lines below
	call blit
	xor a
	ld (ix+4),a
	ld (ix+5),a
se_next:
	ld de,8
	add ix,de
	pop bc
	djnz se_loop
	ret

; draw enabled sprites, 7 first so that sprite 0 ends on top
spr_draw:
	ld a,7
sd_loop:
	ld (sp_n),a
	ld b,a
	inc b
	ld a,(SPRREG+$15)	; enable
sd_bit:
	rrca
	djnz sd_bit		; carry = enable bit n
	call c,spr_one
	ld a,(sp_n)
	dec a
	jp p,sd_loop
	ret

; bit n of VIC register A -> carry.  Keeps HL, DE.
spr_bit:
	push bc
	ld b,a
	ld a,(sp_n)
	inc a
	ld c,a
	ld a,b
sb_l:
	rrca
	dec c
	jr nz,sb_l
	pop bc
	ret

spr_one:
	; flags
	ld c,0
	ld a,(SPRREG+$1C)
	call spr_bit
	jr nc,so_f1
	set 0,c
so_f1:
	ld a,(SPRREG+$1D)
	call spr_bit
	jr nc,so_f2
	set 1,c
so_f2:
	ld a,(SPRREG+$17)
	call spr_bit
	jr nc,so_f3
	set 2,c
so_f3:
	ld a,c
	ld (sp_flags),a
	; colours (+16: sprite palette)
	xor a
	ld (sp_c),a
	ld a,(SPRREG+$25)
	and $0F
	or $10
	ld (sp_c+1),a
	ld a,(sp_n)
	ld e,a
	ld d,0
	ld hl,SPRREG+$27
	add hl,de
	ld a,(hl)
	and $0F
	or $10
	ld (sp_c+2),a
	ld a,(SPRREG+$26)
	and $0F
	or $10
	ld (sp_c+3),a
	; C64 x (9 bit) -> V9990 x = VID_X + (x - 24) * 3 / 2
	ld hl,SPRREG
	add hl,de
	add hl,de
	ld a,(hl)		; x low
	inc hl
	ld b,(hl)		; y
	ld l,a
	ld h,0
	ld a,(SPRREG+$10)
	call spr_bit
	jr nc,so_x8
	inc h
so_x8:
	ld de,-24
	add hl,de		; x - 24 (signed)
	ld d,h
	ld e,l
	add hl,hl
	add hl,de		; * 3
	sra h
	rr l			; / 2
	ld de,VID_X
	add hl,de
	ld (sp_x),hl
	; y: V9990 y = VID_Y + y - 50
	ld l,b
	ld h,0
	ld de,VID_Y-50
	add hl,de
	ld (sp_y),hl
	; size
	ld hl,36
	ld a,(sp_flags)
	bit 1,a
	jr z,so_w
	ld hl,72
so_w:
	ld (sp_w),hl
	ld hl,21
	ld b,1
	bit 2,a
	jr z,so_h
	ld hl,42
	ld b,2
so_h:
	ld (sp_h),hl
	ld a,b
	ld (sp_ymul),a
	; clip against the bitmap window
	ld hl,(sp_x)
	ld de,WIN_X0
	call clip_lo		; HL = first visible column (0..), carry = none
	ret c
	ld (sp_cx0),hl
	ld hl,(sp_x)
	ld de,(sp_w)
	add hl,de		; right edge
	ld de,WIN_X1
	call clip_hi		; HL = columns cut on the right
	ex de,hl
	ld hl,(sp_w)
	or a
	sbc hl,de
	ld de,(sp_cx0)
	or a
	sbc hl,de		; visible width
	ret c
	ret z
	ld (sp_cw),hl
	ld hl,(sp_y)
	ld de,WIN_Y0
	call clip_lo
	ret c
	ld (sp_cy0),hl
	ld hl,(sp_y)
	ld de,(sp_h)
	add hl,de
	ld de,WIN_Y1
	call clip_hi
	ex de,hl
	ld hl,(sp_h)
	or a
	sbc hl,de
	ld de,(sp_cy0)
	or a
	sbc hl,de
	ret c
	ret z
	ld (sp_ch),hl
	; remember the box for erasing next frame
	ld a,(sp_n)
	add a,a
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld ix,OLDBOX
	add ix,de
	ld hl,(sp_x)
	ld de,(sp_cx0)
	add hl,de
	ld (ix+0),l
	ld (ix+1),h
	ld (BLT+4),hl		; DX
	ld hl,(sp_y)
	ld de,(sp_cy0)
	add hl,de
	ld (ix+2),l
	ld (ix+3),h
	ld (BLT+6),hl		; DY
	ld hl,(sp_cw)
	ld (ix+4),l
	ld (ix+5),h
	ld (BLT+8),hl		; NX
	ld hl,(sp_ch)
	ld (ix+6),l
	ld (ix+7),h
	ld (BLT+10),hl		; NY
	; sprite data: pointer at $C3F8+n, data at $C000 + ptr*64 (SEG0+3)
	ld a,SEG0+3
	out (PORT_P2),a
	ld a,(sp_n)
	ld e,a
	ld d,0
	ld hl,$83F8
	add hl,de
	ld l,(hl)
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl		; ptr*64
	ld de,$8000
	add hl,de
	ld (sp_data),hl
	; LMMC with transparency
	call v_wait
	ld a,36
	out (V_SEL),a
	ld hl,BLT+4
	ld bc,8*256+V_REG
	otir			; DX, DY, NX, NY
	xor a
	out (V_REG),a		; ARG
	ld a,$1C
	out (V_REG),a		; LOP: copy, colour 0 transparent
	ld a,$FF
	out (V_REG),a
	out (V_REG),a		; WM
	xor a
	out (V_REG),a
	out (V_REG),a		; FC
	out (V_REG),a
	out (V_REG),a		; BC
	ld a,$10
	out (V_REG),a		; CMD: LMMC
	; stream the visible lines
	ld hl,(sp_cy0)		; first visible output line
	ld a,(sp_ch)
	ld b,a			; lines to send
so_line:
	push bc
	push hl
	ld a,(sp_ymul)		; source row = line / ymul
	dec a
	ld a,l
	jr z,so_row
	srl a
so_row:
	call spr_decode		; SPRLINE = 72 px of source row A
	ld hl,(sp_cx0)
	ld de,SPRLINE
	add hl,de
	ld a,(sp_cw)
	ld b,a
	ld c,V_CMD
	otir
	pop hl
	inc hl
	pop bc
	djnz so_line
	ld a,(RV_CODESEG)	; (render maps SEG_IO/SEG0+3; the caller re-maps)
	ret

; clip_lo: HL = start (signed), DE = window start -> HL = cut amount (>= 0)
; carry if the start is past everything sensible (never here).
clip_lo:
	or a
	sbc hl,de		; start - win
	bit 7,h
	jr nz,cl_neg
	ld hl,0
	or a
	ret
cl_neg:
	ld a,h			; cut = -(start - win)
	cpl
	ld h,a
	ld a,l
	cpl
	ld l,a
	inc hl
	or a
	ret
; clip_hi: HL = end (signed), DE = window end -> HL = cut amount (>= 0)
clip_hi:
	or a
	sbc hl,de		; end - win
	bit 7,h
	jr nz,ch_none
	ret
ch_none:
	ld hl,0
	ret

; decode source row A (0-20) of the current sprite into SPRLINE (36 or 72 px)
spr_decode:
	ld l,a
	add a,a
	add a,l			; row*3
	ld e,a
	ld d,0
	ld hl,(sp_data)
	add hl,de
	; 24 hires-resolution values -> HV
	ld de,HV
	ld a,(sp_flags)
	rrca
	jr nc,sdc_hires
	ld b,3
sdc_mc:
	ld c,(hl)
	inc hl
	push hl
	push bc
	ld b,4
sdc_mc2:
	ld a,c
	rlca
	rlca
	ld c,a
	and 3
	ld hl,sp_c
	add a,l
	ld l,a
	ld a,(hl)
	ld (de),a
	inc de
	ld (de),a
	inc de
	djnz sdc_mc2
	pop bc
	pop hl
	djnz sdc_mc
	jr sdc_out
sdc_hires:
	ld a,(sp_c+2)
	ld (sp_c+4),a		; temp: hires colour
	ld b,3
sdc_hr:
	ld c,(hl)
	inc hl
	push bc
	ld b,8
sdc_hr2:
	rl c
	ld a,0
	jr nc,sdc_hr3
	ld a,(sp_c+4)
sdc_hr3:
	ld (de),a
	inc de
	djnz sdc_hr2
	pop bc
	djnz sdc_hr
sdc_out:
	; HV pairs (a, b) -> a, a|b, b   (x expand: a, a, a, b, b, b)
	ld hl,HV
	ld de,SPRLINE
	ld b,12
	ld a,(sp_flags)
	bit 1,a
	jr nz,sdc_wide
sdc_n:
	ld a,(hl)
	inc hl
	ld (de),a
	inc de
	ld c,(hl)
	inc hl
	or a
	jr nz,sdc_n2
	ld a,c
sdc_n2:
	ld (de),a
	inc de
	ld a,c
	ld (de),a
	inc de
	djnz sdc_n
	ret
sdc_wide:
	ld a,(hl)
	inc hl
	ld (de),a
	inc de
	ld (de),a
	inc de
	ld (de),a
	inc de
	ld a,(hl)
	inc hl
	ld (de),a
	inc de
	ld (de),a
	inc de
	ld (de),a
	inc de
	djnz sdc_wide
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
