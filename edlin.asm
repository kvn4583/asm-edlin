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
	jl end		; quit if there was an error

	; Else store file descriptor in memory
	mov [descriptor], eax

loop:
	; Show marker designating user input
	mov edx, 2		; write 2 bytes
	mov eax, 4
	mov ebx, 1
	mov ecx, marker
	int 0x80

	; read first level of user input
	call readinput

	; if only newline was entered, loop again
	cmp byte [ecx], 10
	je loop

	; If second char is newline, continue to command phase
	inc ecx		; buffer left over from read syscall
	cmp byte [ecx], 10
	je command

	; else restart read input loop
	dec ecx		; reverse increment to restore ecx (necessary?)
	jmp loop	; loop not _start so we don't open the file again

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

	jmp loop

append:
	call readinput

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
	; read file contents
	mov eax, 3
	mov ebx, [descriptor]
	mov ecx, content
	mov edx, 552
	int 0x80

	; output the whole file
	mov edx, eax    	; write number of bytes read
	mov eax, 4			; syscall number for write
	mov ebx, 1			; file descriptor for stdout
	mov ecx, content	; variable to write
	int 0x80			; invoke the kernel

	; reset file pointer
	mov eax, 19           ; lseek system call number
	mov ebx, [descriptor] ; file descriptor
	mov ecx, 0            ; offset (seek from the beginning of the file)
	mov edx, 0            ; whence (SEEK_SET)
	int 0x80              ; invoke the kernel

	; Check for errors in the lseek syscall (in eax)
	cmp eax, -1
	je end 

	jmp loop

end:
	mov eax, 6		; close file
	mov ebx, [descriptor]
	int 0x80

	mov eax, 1		; syscall number for exit
	xor ebx, ebx	; exit code 0
	int 0x80		; invoke the kernel


;; functions

;readfile:
;	mov eax, 3
;	mov ebx, [descriptor]
;	mov ecx, content
;	mov edx, 552
;	int 0x80
;	ret

readinput:
	mov eax, 3
	mov ebx, 0
	mov ecx, input
	mov edx, 80
	int 0x80
	ret


