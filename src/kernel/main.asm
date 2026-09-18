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
VIDEO_MEMORY_END equ VIDEO_MEMORY + SCREEN_ROWS * SCREEN_COLS * 2

MSG_LEN     equ 5 ; length of "KapOS", update if the message changes

; Top-left cell of the message so it lands in the middle of the screen
CENTER_ROW equ (SCREEN_ROWS - 1) / 2
CENTER_COL equ (SCREEN_COLS - MSG_LEN) / 2

; Selector of the flat code descriptor set up by boot.asm's GDT
; (gdt_null = 0x00, gdt_code = 0x08, gdt_data = 0x10). IDT gates need it
; to know which segment their handler code lives in.
CODE_SEG equ 0x08

; 8259 PIC ports
PIC1_CMD  equ 0x20
PIC1_DATA equ 0x21
PIC2_CMD  equ 0xA0
PIC2_DATA equ 0xA1

KBD_DATA_PORT equ 0x60

; ASCII control codes used as the special values in scancode_table
ASCII_BS equ 0x08 ; backspace
ASCII_LF equ 0x0A ; enter/newline

; VGA CRT controller ports, used to move the blinking hardware cursor
VGA_CRTC_INDEX equ 0x3D4
VGA_CRTC_DATA  equ 0x3D5

start:
	; Segment registers (ds/es/ss) and esp were already set up by the
	; bootloader's flat protected-mode descriptors; nothing to do here.

	; Clear screen: 80 * 25 cells, 2 bytes each, written 4 bytes (2 cells) at a time
	mov edi, VIDEO_MEMORY
	mov eax, BLANK_CELL
	mov ecx, (SCREEN_ROWS * SCREEN_COLS) / 2
	rep stosd

	; The hardware text cursor is left wherever the BIOS put it (usually
	; some stray position, not row 0 col 0), and we don't move it again
	; until the console starts - so hide it for now instead of leaving
	; it blinking in the wrong place on the welcome screen.
	call hide_cursor

	; Print message, centered on screen
	mov esi, msg_hello
	mov edi, VIDEO_MEMORY + (CENTER_ROW * SCREEN_COLS + CENTER_COL) * 2
	call print

	; Stays on the welcome screen (console_active = 0) until Enter is
	; pressed; keyboard_isr clears the screen and flips console_active
	; to 1 at that point. cursor_pos is unused until then.

	call remap_pic
	call load_idt

	; Interrupts were left disabled by the bootloader (it did cli before
	; loading its real-mode-only GDT); now that the IDT and PIC are ready,
	; turn them back on so IRQ1 (keyboard) can reach us.
	sti

; Nothing left to do on the main path: the keyboard_isr below does all
; the work whenever a key is pressed. hlt parks the CPU until the next
; interrupt instead of spinning a busy loop.
.halt_loop:
	hlt
	jmp .halt_loop

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

; ---------------------------------------------------------------
; Console output
; ---------------------------------------------------------------
; Clears the welcome screen and switches the keyboard handler from
; "wait for Enter" mode into normal typing mode.
start_console:
	push edi
	push eax
	push ecx

	mov edi, VIDEO_MEMORY
	mov eax, BLANK_CELL
	mov ecx, (SCREEN_ROWS * SCREEN_COLS) / 2
	rep stosd

	mov dword [cursor_pos], VIDEO_MEMORY
	mov byte [console_active], 1

	call show_cursor

	mov al, '>' ; prompt for the first instruction
	call console_putchar

	pop ecx
	pop eax
	pop edi
	ret

; Hides the blinking hardware cursor (CRT cursor start register, bit 5).
hide_cursor:
	push eax
	push edx

	mov dx, VGA_CRTC_INDEX
	mov al, 0x0A ; cursor start register
	out dx, al
	mov dx, VGA_CRTC_DATA
	mov al, 0x20 ; bit 5 set = cursor disabled
	out dx, al

	pop edx
	pop eax
	ret

; Shows the hardware cursor as a thin underline (scanlines 14-15 of the
; 16-scanline text cell) and lets sync_hw_cursor position it.
show_cursor:
	push eax
	push edx

	mov dx, VGA_CRTC_INDEX
	mov al, 0x0A ; cursor start register
	out dx, al
	mov dx, VGA_CRTC_DATA
	mov al, 14
	out dx, al

	mov dx, VGA_CRTC_INDEX
	mov al, 0x0B ; cursor end register
	out dx, al
	mov dx, VGA_CRTC_DATA
	mov al, 15
	out dx, al

	pop edx
	pop eax
	ret

; Moves the hardware cursor to match [cursor_pos]. Called after every
; write that can change cursor_pos, so the blinking cursor always shows
; where the next character will land.
sync_hw_cursor:
	push eax
	push ebx
	push edx

	mov eax, [cursor_pos]
	sub eax, VIDEO_MEMORY
	shr eax, 1     ; eax = cell index (row * SCREEN_COLS + col)
	mov ebx, eax

	mov dx, VGA_CRTC_INDEX
	mov al, 0x0E   ; cursor location high byte
	out dx, al
	mov dx, VGA_CRTC_DATA
	mov eax, ebx
	shr eax, 8
	out dx, al

	mov dx, VGA_CRTC_INDEX
	mov al, 0x0F   ; cursor location low byte
	out dx, al
	mov dx, VGA_CRTC_DATA
	mov eax, ebx
	out dx, al

	pop edx
	pop ebx
	pop eax
	ret

; Writes one character at the current cursor position and advances it.
; Since the VGA buffer is one contiguous array of cells, advancing past
; the last column naturally continues at column 0 of the next row - no
; per-row bookkeeping needed. Running off the last row just wraps back
; to the top of the screen for now; scrolling is a later step.
; Params:
;	- al = character to print
console_putchar:
	push edi

	mov edi, [cursor_pos]
	mov ah, 0x07 ; gray on black
	mov [edi], ax
	add edi, 2

	cmp edi, VIDEO_MEMORY_END
	jb .store
	mov edi, VIDEO_MEMORY

.store:
	mov [cursor_pos], edi
	call sync_hw_cursor
	pop edi
	ret

; Moves the cursor to column 0 of the next row (Enter/newline).
; Wraps back to the top of the screen past the last row, same as
; console_putchar.
console_newline:
	push eax
	push ecx
	push edx

	mov eax, [cursor_pos]
	sub eax, VIDEO_MEMORY
	mov ecx, SCREEN_COLS * 2
	xor edx, edx
	div ecx      ; eax = current row (edx, the column, is discarded)
	inc eax
	mul ecx      ; eax = (row + 1) * SCREEN_COLS * 2
	add eax, VIDEO_MEMORY

	cmp eax, VIDEO_MEMORY_END
	jb .store
	mov eax, VIDEO_MEMORY

.store:
	mov [cursor_pos], eax
	call sync_hw_cursor

	pop edx
	pop ecx
	pop eax
	ret

; Moves the cursor back one cell and blanks it (Backspace). Does
; nothing if the cursor is already at the very start of the screen.
console_backspace:
	push eax
	push edi

	mov eax, [cursor_pos]
	cmp eax, VIDEO_MEMORY
	jbe .done

	sub eax, 2
	mov [cursor_pos], eax

	mov edi, eax
	mov word [edi], 0x0720 ; blank cell: space (0x20), gray on black (0x07)
	call sync_hw_cursor

.done:
	pop edi
	pop eax
	ret

; ---------------------------------------------------------------
; 8259 PIC remap
; ---------------------------------------------------------------
; By default the PIC fires IRQ0-15 on interrupt vectors 0x08-0x0F and
; 0x70-0x77, which overlap CPU exception vectors (0x00-0x1F). Remap
; them to 0x20-0x2F so hardware interrupts and CPU exceptions never
; collide. Only IRQ1 (keyboard) is left unmasked; everything else is
; masked off since nothing handles it yet.
remap_pic:
	push eax

	mov al, 0x11 ; ICW1: start init sequence, expect ICW4
	out PIC1_CMD, al
	out PIC2_CMD, al

	mov al, 0x20 ; ICW2: master PIC vector offset -> IRQ0 = int 0x20
	out PIC1_DATA, al
	mov al, 0x28 ; ICW2: slave PIC vector offset -> IRQ8 = int 0x28
	out PIC2_DATA, al

	mov al, 0x04 ; ICW3: master has a slave wired to its IRQ2 line (bit 2)
	out PIC1_DATA, al
	mov al, 0x02 ; ICW3: slave identifies itself as being on master's IRQ2
	out PIC2_DATA, al

	mov al, 0x01 ; ICW4: 8086/88 mode
	out PIC1_DATA, al
	out PIC2_DATA, al

	mov al, 11111101b ; OCW1: mask every IRQ except IRQ1 (keyboard)
	out PIC1_DATA, al
	mov al, 11111111b ; OCW1: mask every IRQ on the slave PIC
	out PIC2_DATA, al

	pop eax
	ret

; ---------------------------------------------------------------
; IDT
; ---------------------------------------------------------------
; NASM refuses bitwise/shift operators on label addresses (even in flat
; binary mode), so the table can't be built as static data - a gate
; needs its handler address split into low16/high16, which needs a
; runtime shr. Instead, reserve the space and fill it in with a loop:
; every vector defaults to default_isr, then vector 0x21 (IRQ1 after
; the PIC remap above) is overwritten with the real keyboard handler.
load_idt:
	mov edi, idt_start
	mov ecx, 256

.fill_loop:
	mov eax, default_isr
	mov ebx, edi
	call set_idt_gate
	add edi, 8
	dec ecx
	jnz .fill_loop

	mov eax, keyboard_isr
	mov ebx, idt_start + 0x21 * 8
	call set_idt_gate

	lidt [idt_descriptor]
	ret

; Writes one 8-byte interrupt-gate descriptor.
; Format: offset 0-15, selector, zero, type/attr (0x8E = present,
; ring 0, 32-bit interrupt gate), offset 16-31.
; Params:
;	- eax = handler address
;	- ebx = pointer to the 8-byte entry to fill
set_idt_gate:
	mov word [ebx], ax        ; offset 0-15
	mov word [ebx + 2], CODE_SEG
	mov byte [ebx + 4], 0
	mov byte [ebx + 5], 0x8E
	shr eax, 16
	mov word [ebx + 6], ax    ; offset 16-31
	ret

idt_start:
	times 256 * 8 db 0
idt_end:

idt_descriptor:
	dw idt_end - idt_start - 1 ; size of IDT minus 1, as lidt expects
	dd idt_start                ; linear address of the table (org 0x10000 makes this absolute)

; Catches any interrupt/exception we don't otherwise handle and just
; returns. Note: exceptions that push an error code (8, 10-14, 17)
; aren't popped here, so this only stays safe as long as none of them
; actually fire - fine for now since this kernel does nothing that
; triggers them.
default_isr:
	iretd

; IRQ1: a key was pressed or released on the PS/2 keyboard.
keyboard_isr:
	pushad

	in al, KBD_DATA_PORT

	test al, 0x80 ; bit 7 set = key release; only handle presses
	jnz .done

	movzx ebx, al
	cmp ebx, SCANCODE_TABLE_LEN
	jae .done

	mov al, [scancode_table + ebx]
	test al, al ; 0 = no mapping for this scancode yet
	jz .done

	cmp byte [console_active], 0
	jne .console_input

	; Still on the welcome screen: any key other than Enter is ignored.
	cmp al, ASCII_LF
	jne .done
	call start_console
	jmp .done

.console_input:
	cmp al, ASCII_LF
	je .handle_enter
	cmp al, ASCII_BS
	je .handle_backspace

	call console_putchar
	jmp .done

.handle_enter:
	call console_newline

	mov al, '0' ; placeholder result for the instruction just entered
	call console_putchar

	call console_newline

	mov al, '>' ; prompt for the next instruction
	call console_putchar

	jmp .done

.handle_backspace:
	call console_backspace

.done:
	mov al, 0x20 ; EOI (End Of Interrupt) so the PIC will deliver IRQ1 again
	out PIC1_CMD, al
	popad
	iretd

; ---------------------------------------------------------------
; Data
; ---------------------------------------------------------------
msg_hello: db 'KapOS', 0

cursor_pos: dd 0

; 0 = still on the welcome screen (waiting for Enter), 1 = console is
; taking input normally.
console_active: db 0

; Maps PS/2 scan code set 1 "make" codes to lowercase ASCII letters plus
; Enter, Backspace and Space. Everything else (digits, punctuation,
; Shift, Tab, ...) is 0 and gets ignored.
scancode_table:
	db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,ASCII_BS,0                       ; 0x00-0x0F
	db 'q','w','e','r','t','y','u','i','o','p',0,0,ASCII_LF,0,'a','s' ; 0x10-0x1F
	db 'd','f','g','h','j','k','l',0,0,0,0,0,'z','x','c','v'          ; 0x20-0x2F
	db 'b','n','m',0,0,0,0,0,0,0x20                                    ; 0x30-0x39
SCANCODE_TABLE_LEN equ $ - scancode_table
