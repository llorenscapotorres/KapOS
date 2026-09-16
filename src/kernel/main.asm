; Tells assembler to emit 16-bit code (real mode).
; Bootloader runs in real mode before switching to protected mode.
bits 16

; Kernel is loaded at physical address 0x10000 (segment 0x1000, offset 0x0000)
; see boot.asm: jmp 0x1000:0x0000
org 0x0000

; define new line in BIOS environment
%define ENDL 0x0D, 0x0A

start:
	; ds must match the segment the kernel is actually loaded at (0x1000),
	; since labels are computed as offsets from org 0x0000 within that segment
	mov ax, 0x1000
	mov ds, ax

	mov ax, 0
	mov es, ax
	mov ss, ax
	mov sp, 0x7C00

	; Clean Screen
	mov ax, 0xB800
	mov es, ax
	xor di, di

	mov ax, 0x0720 ; space + grey on black
	mov cx, 80 * 25

	rep stosw

	; Print Message
	mov si, msg_hello
	call print

	; stops CPU from executing (it can be resumed by an interrupt)
	cli
	hlt
	jmp $

; Prints a string to the screen.
; Params:
;	- ds:si points to string
print:
	; Save registers we will modify

	; Stack pointer (sp) is currently at 0x7C00
	; After push si: value of si is stored at address 0x7BFE-0x7BFF, sp becomes 0x7BFE 
	push si
	; After push ax: value of ax is stored at address 0x7BFC-0x7BFD, sp becomes 0x7BFC
	; Stack now contains: [0x7BFC] = ax, [0x7BFC] = si
	push ax

	push di
	
	xor di, di ; start at position 0 in screen

.loop:
	; these instructions load a byte/word/double-word from [ds:si] into AL/AX/EAX
	; then increment si by the number of bytes loaded
	lodsb ; loads next character into AL and increment si
	
	test al, al ; verfy if next character is NULL (0x00)
	jz .done ; jumps to destination if zero flag is set (character is NULL)

	mov ah, 0x07 ; gray on black
	stosw ; [ES:DI] = AX, DI += 2
	
	jmp .loop ; loop back to load next character

.done:
	; Restore registers to their original values

	pop di

	; pop ax: retrieves value from address 0x7BFC-0x7BFD into ax, sp becomes 0x7BFE
	pop ax
	; pop si: retrieves value from address 0x7BFE-0x7BFF into si, sp becomes 0x7C00
	pop si
	; Stack is now empty, back to original state
	ret

msg_hello: db 'KapOS', 0