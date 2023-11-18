; line editor that can append to file, prepend to file, print file, and quit

; a for append
; i for insert (prepend)
; p for print
; q for quit (and write to file)

section .bss
	input resb 80		; limit lines to 80 characters
	content resb 552	; file contents
	descriptor resb 4	; file descriptor

section .data
	marker db "> ", 0
	filename db "out.txt", 0

section .text
	global _start


_start:

	; Open file for reading and writing
	mov eax, 5			; System call number for open
	mov ebx, filename	; Pointer to the filename
	mov ecx, 1026		; bitwise 0x2|0x400 (read/write, append)
	;mov edx, 0644
	int 0x80			; Call the kernel

    ; Check for errors in the open syscall (in eax)
	cmp eax, 0
	jl  end		; quit if there was an error

	; Else store file descriptor in memory
	mov [descriptor], eax

	; Show marker designating user input
	mov edx, 2		; write 2 bytes
	mov eax, 4
	mov ebx, 1
	mov ecx, marker
	int 0x80

	; read first level of user input
	push 80
	push input
	push 0
	call read

	; If second char is newline, continue to command phase
	; else restart read input loop
	inc ecx		; buffer left over from read syscall
	cmp byte [ecx], 10
	je command
	jmp _start


command:
	dec ecx

	; if a then append
	cmp byte [ecx], 97
	je append

	; else if p then print
	cmp byte [ecx], 112
	je print

	; else if q then quit
	cmp byte [ecx], 113
	je end

	jmp _start


append:
	; read 80 chars of input for one line
	push 80
	push input
	push 0
	call read

	; check for newline in second byte of input
	inc ecx		; buffer left over from read syscall
	cmp byte [ecx], 10

	; if . then stop appending
	dec ecx
	cmp byte [ecx], 46
	je _start

	; write one line at a time
	mov edx, eax    	; write number of bytes read
	mov eax, 4			; syscall number for write
	mov ebx, [descriptor]
	mov ecx, input		; variable to write
	int 0x80			; invoke the kernel

	jmp append		; keep appending


print:
	push 552
	push content
	mov eax, [descriptor]	; can't push onto stack directly
	push eax
	call read

	; output the whole file
	mov edx, eax    	; write number of bytes read
	mov eax, 4			; syscall number for write
	mov ebx, 1			; file descriptor for stdout
	mov ecx, content	; variable to write
	int 0x80			; invoke the kernel

	jmp _start

end:
	mov eax, 6		; close file
	mov ebx, [descriptor]
	int 0x80

	mov eax, 1		; syscall number for exit
	xor ebx, ebx	; exit code 0
	int 0x80		; invoke the kernel

;; functions

read:
	; arg1 - file descriptor (not pointer)
	; arg2 - buffer to read into (pointer)
	; arg3 - number of bytes to read
	push ebp
	mov ebp, esp

	mov eax, 3
	mov ebx, [ebp + 8]
	mov ecx, [ebp + 12]
	mov edx, [ebp + 16]
	int 0x80

	mov esp, ebp
	pop ebp
	ret


