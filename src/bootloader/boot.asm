; Tells assembler where we expect our code to be loaded.
; BIOS loads the bootloader at address 0x7C00 in memory.
; The assembler uses this information to calculate label addresses correctly.
org 0x7C00

; Tells assembler to emit 16-bit code (real mode).
; Bootloader runs in real mode before switching to protected mode.
bits 16

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

	; Read header values
	mov eax, [0x7E00] ; kernel_sector
	mov ecx, [0x7E04] ; kernel_size

	; Compute how many sectors to read
	; sectors = (kernel_size + 511) / 512
	add ecx, 511
	shr ecx, 9

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

	; ---------------------------------------------------------------
	; Enable A20 line
	; ---------------------------------------------------------------
	; On real 8086 CPUs, memory addresses wrapped around at 1MB
	; (address bit 20 was ignored). Modern CPUs keep this "feature"
	; disabled by default for backwards compatibility, so anything
	; using linear addresses at/above 1MB (like our flat protected
	; mode GDT) needs it turned on first.
	; Fast A20 gate: bit 1 of port 0x92 enables the A20 line.
	in al, 0x92
	or al, 2
	out 0x92, al

	; ---------------------------------------------------------------
	; Switch to protected mode
	; ---------------------------------------------------------------
	cli ; disable interrupts: the real-mode IDT is about to become invalid

	lgdt [gdt_descriptor] ; load GDT: cs still real-mode until the far jump below

	mov eax, cr0
	or eax, 1 ; set PE (Protection Enable) bit
	mov cr0, eax

	; Far jump into 32-bit code. This is required (not just a style
	; choice): it flushes the CPU's instruction prefetch queue and
	; loads CS with the new descriptor, actually entering 32-bit mode.
	jmp CODE_SEG:protected_mode_start

disk_error:
	hlt
	jmp $

; ---------------------------------------------------------------
; Global Descriptor Table
; ---------------------------------------------------------------
gdt_start:

gdt_null:               ; mandatory null descriptor, selector 0x00
	dq 0x0

gdt_code:                ; selector = gdt_code - gdt_start
	dw 0xFFFF             ; limit 0-15   -> 0xFFFFF with 4KB granularity = 4GB
	dw 0x0                ; base 0-15    -> 0
	db 0x0                ; base 16-23   -> 0
	db 10011010b          ; access: present, ring0, code/data, executable, readable
	db 11001111b          ; flags (4KB granularity, 32-bit) + limit 16-19
	db 0x0                ; base 24-31   -> 0

gdt_data:                ; selector = gdt_data - gdt_start
	dw 0xFFFF
	dw 0x0
	db 0x0
	db 10010010b          ; access: present, ring0, code/data, writable
	db 11001111b
	db 0x0

gdt_end:

gdt_descriptor:
	dw gdt_end - gdt_start - 1 ; size of GDT minus 1, as lgdt expects
	dd gdt_start                ; linear address of the table (org 0x7C00 makes this absolute)

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start

; ---------------------------------------------------------------
; 32-bit protected mode entry point
; ---------------------------------------------------------------
bits 32

protected_mode_start:
	; Reload every segment register with the flat data selector.
	; Real-mode segment:offset addressing no longer applies: these
	; selectors now index descriptors in the GDT above.
	mov ax, DATA_SEG
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov fs, ax
	mov gs, ax

	mov esp, 0x90000 ; fresh protected-mode stack, well above the bootloader/kernel

	; Jump into the kernel. It was loaded at physical 0x10000
	; (segment 0x1000, offset 0x0000 in real mode); with a flat
	; descriptor (base 0) that is simply the linear address 0x10000.
	jmp CODE_SEG:0x10000

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
