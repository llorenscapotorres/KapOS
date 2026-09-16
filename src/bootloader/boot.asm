; Tells assembler where we expect our code to be loaded.
; BIOS loads the bootloader at address 0x7C00 in memory.
; The assembler uses this information to calculate label addresses correctly.
org 0x7C00

; Tells assembler to emit 16-bit code (real mode).
; Bootloader runs in real mode before switching to protected mode.
bits 16

%define ENDL 0x0D, 0x0A

start:
	jmp bootloader

print:
	push si
	push ax
.loop:
	lodsb
	or al, al
	jz .done
	mov ah, 0x0E
	int 0x10
	jmp .loop
.done:
	pop ax
	pop si
	ret

bootloader:

	; Setup data segment registers for proper memory access.
	; In real mode: physical address = segment_register * 0x10 + offset
	; We set both to 0 so we can access memory from address 0x00000 onwards
	
	mov ax, 0 ; can't write to ds/es directly

	; ds (Data Segment) = 0
	; Now data accesses use physical addresses directly
	mov ds, ax

	; es (Extra Segment) = 0
	; Alternative segment register for data operations
	mov es, ax

	; Setup stack segment and pointer for function calls and local variables.
	; Stack grows downward in memory (from high to low addresses).

	; ss (Stack Segment) = 0
	; Stack base address = 0 * 0x10 = 0x00000
	mov ss, ax

	; sp (Stack Pointer) = 0x7C00
	; Stack begins at 0x7C00 and grows downwards.
	; This places the stack just below our bootloader code, keeping it safe.
	; When PUSH happens, stack pointer decreases (grows down).
	mov sp, 0x7C00

	mov si, msg_reading_header
	call print

	; Read sector 1 (image_header) at 0x7E00
	mov ax, 0
	mov es, ax
	mov bx, 0x7E00

	mov ah, 0x02 ; function: read sectors
	mov al, 1 ; read sector 1
	mov ch, 0 ; cilindre 0
	mov cl, 2 ; sector 1
	mov dh, 0 ; head 0
	mov dl, 0x80 ; main disk
	int 0x13

	jc disk_error ; jump if there is an error

	mov si, msg_header_ok
	call print

	; Read header values
	mov eax, [0x7E00] ; kernel_sector
	mov ecx, [0x7E04] ; kernel_size

	; Compute how many sectors to read
	; sectors = (kernel_size + 511) / 512
	add ecx, 511
	shr ecx, 9

	mov si, msg_reading_kernel
	call print

	; Load kernel in 0x10000
	mov ax, 0x1000
	mov es, ax
	xor bx, bx

	; Read kernel
	mov ah, 0x02
	mov al, cl ; number of sectors
	mov cx, ax ; eax contains kernel_sector

	; Convert sector to CHS
	mov cl, byte [0x7E00] ; kernel_sector in CX (only lower bits)
	inc cl ; BIOS use 1-based
	mov ch, 0 ; cilindre 0
	mov dh, 0 ; head 0
	mov dl, 0x80
	int 0x13

	mov si, msg_kernel_ok
	call print

	; jump into kernel
	jmp 0x1000:0x0000 ; segment:offset

disk_error:
	mov si, msg_error
	call print
	hlt
	jmp $

msg_reading_header: db 'Reading header...', ENDL, 0
msg_header_ok: db 'Header OK', ENDL, 0
msg_reading_kernel: db 'Reading kernel...', ENDL, 0
msg_kernel_ok: db 'Kernel loaded, jumping!', ENDL, 0
msg_error: db 'DISK ERROR', ENDL, 0

; repeats given instruction or piece of data a number of times
; $ is an special symbol which is equal to the memory offset of the current line
; $$ is an special symbol which is equal to the memory offset of the begging of the current section (in our case, program)
; $ - $$ gives the size of our program so far (in bytes)
; we pad with zeros because BIOS expects bootloader to be exactly 512 bytes
; bytes 0-509 contain our code/data, bytes 510-511 are reserved for the boot signature
times 510-($-$$) db 0
; 0xAA55 is the magic number that tells BIOS this sector is bootable
; it must be located at bytes 510-511 of the bootloader
dw 0xAA55
