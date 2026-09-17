; The bootloader now switches to 32-bit protected mode before jumping
; here, so the kernel is compiled as 32-bit code.
bits 32

; Kernel is loaded at physical address 0x10000 (see boot.asm: jmp CODE_SEG:0x10000).
; In protected mode, segments are flat (base 0), so the linear address
; equals this org value directly - no segment setup is needed.
org 0x10000

VIDEO_MEMORY equ 0xB8000
BLANK_CELL   equ 0x07200720 ; two "space, grey on black" cells packed into one dword

SCREEN_COLS equ 80
SCREEN_ROWS equ 25
MSG_LEN     equ 5 ; length of "KapOS", update if the message changes

; Top-left cell of the message so it lands in the middle of the screen
CENTER_ROW equ (SCREEN_ROWS - 1) / 2
CENTER_COL equ (SCREEN_COLS - MSG_LEN) / 2

start:
	; Segment registers (ds/es/ss) and esp were already set up by the
	; bootloader's flat protected-mode descriptors; nothing to do here.

	; Clear screen: 80 * 25 cells, 2 bytes each, written 4 bytes (2 cells) at a time
	mov edi, VIDEO_MEMORY
	mov eax, BLANK_CELL
	mov ecx, (SCREEN_ROWS * SCREEN_COLS) / 2
	rep stosd

	; Print message, centered on screen
	mov esi, msg_hello
	mov edi, VIDEO_MEMORY + (CENTER_ROW * SCREEN_COLS + CENTER_COL) * 2
	call print

	; stops CPU from executing (it can be resumed by an interrupt)
	cli
	hlt
	jmp $

; Prints a string directly into VGA text memory.
; Params:
;	- esi points to string
;	- edi points to the video memory position to start writing at
print:
	push eax

.loop:
	lodsb ; loads next character into AL and increments esi

	test al, al ; verify if next character is NULL (0x00)
	jz .done ; jump to destination if zero flag is set (character is NULL)

	mov ah, 0x07 ; gray on black
	stosw ; [ES:EDI] = AX, EDI += 2

	jmp .loop ; loop back to load next character

.done:
	pop eax
	ret

msg_hello: db 'KapOS', 0
