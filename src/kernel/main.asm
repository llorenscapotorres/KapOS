; Tells assembler where we expect our code to be loaded.
; BIOS loads the bootloader at address 0x7C00 in memory.
; The assembler uses this information to calculate label addresses correctly.
org 0x7C00

; Tells assembler to emit 16-bit code (real mode).
; Bootloader runs in real mode before switching to protected mode.
bits 16

; define new line in BIOS environment
%define ENDL 0x0D, 0x0A

start:
	jmp bootloader

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

.loop:
	; these instructions load a byte/word/double-word from [ds:si] into AL/AX/EAX
	; then increment si by the number of bytes loaded
	lodsb ; loads next character into AL and increment si
	
	or al, al ; verfy if next character is NULL (0x00)
	jz .done ; jumps to destination if zero flag is set (character is NULL)

	mov ah, 0x0E ; Function: teletype print
	mov bh, 0x00 ; page number
	int 0x10 ; Call SeaBIOS print interrupt
	
	jmp .loop ; loop back to load next character

.done:
	; Restore registers to their original values

	; pop ax: retrieves value from address 0x7BFC-0x7BFD into ax, sp becomes 0x7BFE
	pop ax
	; pop si: retrieves value from address 0x7BFE-0x7BFF into si, sp becomes 0x7C00
	pop si
	; Stack is now empty, back to original state
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

	; print message
	mov si, msg_hello
	call print

	; stops CPU from executing (it can be resumed by an interrupt)
	hlt

.halt:
	; jumps to given location, unconditionally
	jmp .halt

msg_hello: db 'Saluton Mondo de KapOS en Esperanto!', 0

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
