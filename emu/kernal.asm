; C64 KERNAL calls used by Last Ninja, done on the MSX side.
; setpc jumps to kernal_trap when the 6502 jumps into $E000-$FFFF while the
; KERNAL is mapped (there is no KERNAL ROM: that RAM holds the game bitmap).
; Each routine works on the 6502 registers (RV_A, X = B, Y = C, RV_C), then
; kernal_trap returns like RTS.  Files come from the MSX-DOS disk through the
; DOS bridge (FCB functions), one 4K block at a time.

kernal_trap:			; HL = 6502 target address
	push hl
	ex de,hl		; DE = target
	ld hl,k_table
kt_find:
	ld a,(hl)
	inc hl
	or (hl)
	jr z,kt_unknown
	dec hl
	ld a,(hl)
	cp e
	jr nz,kt_next
	inc hl
	ld a,(hl)
	cp d
	jr nz,kt_next1
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	pop hl
	ex de,hl
	ld de,kt_rts
	push de
	jp (hl)			; routine, then kt_rts
kt_next:
	inc hl
kt_next1:
	inc hl
	inc hl
	inc hl
	jr kt_find
kt_unknown:
	pop hl
	ld (k_bad),hl		; stop: unknown KERNAL routine (address in k_bad)
kt_halt:
	jr kt_halt
kt_rts:				; pull the return address, PC = it + 1
	ld hl,(RV_S)
	inc l
	ld a,(hl)
	inc l
	ld h,(hl)
	ld l,a
	ld a,(RV_S)
	add a,2
	ld (RV_S),a
	inc hl
	jp setpc

k_table:
	dw $FF90, k_ok		; SETMSG
	dw $FFBA, k_setlfs	; SETLFS
	dw $FFBD, k_setnam	; SETNAM
	dw $FFC0, k_openf	; OPEN
	dw $FFC3, k_closef	; CLOSE
	dw $FFC6, k_ok		; CHKIN
	dw $FFCC, k_ok		; CLRCHN
	dw $FFCF, k_chrin	; CHRIN
	dw $FFB7, k_readst	; READST
	dw $FFD5, k_load	; LOAD
	dw $FFE4, k_getin	; GETIN (no keys)
	dw $FFD2, k_ok		; CHROUT (not shown)
	dw $FFE7, k_closef	; CLALL
	dw $F642, k_ok		; end of the hf loader (KERNAL load tail)
	dw 0

k_ok:
	xor a
	ld (RV_C),a
	ret
k_err:				; A = KERNAL error code, carry set
	db $FD,$6F		; ld iyl,a (6502 A)
	ld a,$FF
	ld (RV_C),a
	ret

k_setlfs:
	ld a,b
	ld (k_dev),a
	ld a,c
	ld (k_sa),a
	jr k_ok

k_setnam:			; A = length, X/Y = name
	db $FD,$7D		; ld a,iyl (6502 A)
	cp 16
	jr c,ksn_len
	ld a,15
ksn_len:
	ld (k_fnlen),a
	or a
	jr z,k_ok
	push bc
	ld l,b
	ld h,c
	ld de,k_fname
	ld b,a
ksn_loop:
	call rd_any
	ld (de),a
	inc hl
	inc de
	djnz ksn_loop
	pop bc
	jr k_ok

k_openf:
	call f_open
	jr nz,k_ok
	ld a,4			; file not found
	jr k_err

k_closef:
	call f_close
	jr k_ok

k_chrin:
	call f_getc
	jr nc,kc_ok
	xor a
kc_ok:
	db $FD,$6F		; ld iyl,a (6502 A)
	db $DD,$67		; ld ixh,a (N source)
	db $DD,$6F		; ld ixl,a (Z source)
	jr k_ok

k_readst:
	ld a,($0090)		; ST (6502 page 0 is Z80 page 0)
	db $FD,$6F		; ld iyl,a (6502 A)
	db $DD,$67		; ld ixh,a (N source)
	db $DD,$6F		; ld ixl,a (Z source)
	jr k_ok

k_getin:
	xor a
	db $FD,$6F		; ld iyl,a (6502 A)
	db $DD,$67		; ld ixh,a (N source)
	db $DD,$6F		; ld ixl,a (Z source)
	jr k_ok

; LOAD: A = 0 (load), X/Y = address if the secondary address is 0
k_load:
	call f_open
	ld a,4
	jr z,k_err
	call f_getc		; file's load address
	ld e,a			; (f_getc keeps DE, not HL)
	call f_getc
	ld h,a
	ld l,e
	ld a,(k_sa)
	or a
	jr nz,kl_hdr
	ld l,b
	ld h,c
kl_hdr:
	ld (k_addr),hl
kl_loop:
	call f_getc
	jr c,kl_end
	ld hl,(k_addr)
	call wr_ram
	inc hl
	ld (k_addr),hl
	jr kl_loop
kl_end:
	call f_close
	ld hl,(k_addr)		; end address in X/Y
	ld b,l
	ld c,h
	ld a,$40
	ld ($0090),a
	jp k_ok

; write A to 6502 RAM at HL (no I/O), marks dirty pages.  Keeps BC, DE, HL.
wr_ram:
	push af
	ld a,h
	cp $40
	jr nc,wrr_hi
	pop af
	ld (hl),a
	ret
wrr_hi:
	pop af
	ld (RV_T),a
	jp wh_ram

; ---- files on the MSX-DOS disk --------------------------------------------
; f_open: open k_fname -> NZ if ok.  Keeps BC.
f_open:
	push bc
	call f_close
	ld hl,FCB		; FCB: drive 0, name padded with spaces, ext blank
	ld (hl),0
	inc hl
	ld b,11
fo_clr:
	ld (hl),' '
	inc hl
	djnz fo_clr
	ld b,37-12
fo_clr2:
	ld (hl),0
	inc hl
	djnz fo_clr2
	ld a,(k_fnlen)
	cp 9
	jr c,fo_len
	ld a,8
fo_len:
	or a
	jr z,fo_fail
	ld b,a
	ld hl,k_fname
	ld de,FCB+1
fo_name:
	ld a,(hl)
	and $7F
	cp 'a'
	jr c,fo_up
	cp 'z'+1
	jr nc,fo_up
	sub $20
fo_up:
	ld (de),a
	inc hl
	inc de
	djnz fo_name
	ld de,FCB
	ld c,$0F		; _FOPEN
	call DOSRT
	or a
	jr nz,fo_fail
	ld hl,1
	ld (FCB+14),hl		; record size 1
	ld hl,0
	ld (FCB+33),hl		; random record 0
	ld (FCB+35),hl
	ld (k_pos),hl
	ld (k_len),hl
	xor a
	ld (k_eof),a
	inc a
	ld (k_open),a
	pop bc
	or a			; NZ
	ret
fo_fail:
	pop bc
	xor a			; Z
	ret

f_close:			; keeps BC
	ld a,(k_open)
	or a
	ret z
	push bc
	xor a
	ld (k_open),a
	ld de,FCB
	ld c,$10		; _FCLOSE
	call DOSRT
	pop bc
	ret

; next file byte -> A, carry set at end of file.  Keeps BC, DE.
f_getc:
	push de
	ld hl,(k_pos)
	ld de,(k_len)
	or a
	sbc hl,de
	jr nz,fg_have
	ld a,(k_eof)
	or a
	jr nz,fg_end
	call f_fill
	ld hl,(k_len)
	ld a,h
	or l
	jr z,fg_end
fg_have:
	ld hl,(k_pos)
	ld de,FBUF
	add hl,de
	ld a,(hl)
	ld hl,(k_pos)
	inc hl
	ld (k_pos),hl
	ld de,(k_len)
	or a			; (A kept: flags only)
	push af
	sbc hl,de
	jr nz,fg_ok
	ld a,(k_eof)		; last byte of the file: ST = EOF
	or a
	jr z,fg_ok
	ld hl,$0090
	set 6,(hl)
fg_ok:
	pop af
	pop de
	or a			; carry clear
	ret
fg_end:
	pop de
	scf
	ret

f_fill:				; next block into FBUF.  Keeps BC.
	push bc
	ld de,FBUF
	ld c,$1A		; _SETDTA
	call DOSRT
	ld de,FCB
	ld hl,FBUF_LEN
	ld c,$27		; _RDBLK
	call DOSRT
	ld (k_len),hl
	ld de,FBUF_LEN
	or a
	sbc hl,de
	jr z,ff_more
	ld a,1
	ld (k_eof),a
ff_more:
	ld hl,0
	ld (k_pos),hl
	pop bc
	ret
