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
	marker db '> ', 0
	filename db 'out.txt', 0
	;content db 100

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


	; read input--File descriptor for stdin is 0
	mov eax, 3		; syscall number for read
	mov ebx, 0		; file descriptor for stdin
	mov ecx, input	; variable to store input
	mov edx, 80		; read 80 bytes
	int 0x80		; invoke the kernel

	; If second char is newline, continue to command phase
	; else restart read input loop
	inc ecx
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
	; read input--File descriptor for stdin is 0
	mov eax, 3		; syscall number for read
	mov ebx, 0		; file descriptor for stdin
	mov ecx, input	; variable to store input
	mov edx, 80		; read 80 bytes
	int 0x80		; invoke the kernel

	mov edx, eax    	; write number of bytes read
	mov eax, 4			; syscall number for write
	mov ebx, [descriptor]
	mov ecx, input	; variable to write
	int 0x80			; invoke the kernel

	jmp _start

print:
	; Read from the file
	mov ebx, [descriptor]    ; File descriptor (from open syscall)
	mov eax, 3               ; System call number for read
	mov ecx, content         ; Buffer to read into
	mov edx, 552             ; Number of bytes to read (adjust as needed)
	int 0x80                 ; Call the kernel

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
