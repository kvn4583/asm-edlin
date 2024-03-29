; line editor that can append to file, prepend to file, print file, and quit

; a for append
; i for insert (prepend)
; p for print
; q for quit (and write to file)

section .bss
	descriptor resb 4	; file descriptor
	filesize resb 4		; size of previous file contents
	oldfilesize resb 4	; size of previous file contents to append (insert mode)
	progbreak resb 4	; address for end of data segment
	argsize resb 4		; number of chars in filename
	content resb 4		; Pointer to content in heap
	filename resb FILENAME_LIMIT	; max length of filename
	input resb LINE_LENGTH		; limit lines to 80 characters

section .data
	FILENAME_LIMIT	equ	7	; For ascii representation add 48 or '0'
	LINE_LENGTH	equ	100	; char limit for each line of user input
	marker		db	"> ", 0
	err_msg_noargs	db	"ERROR: Missing filename; Exactly 1 argument required", 10, 0
	size_msg_noargs	equ	$-err_msg_noargs
	err_msg_open	db	"ERROR: Failed to open file", 10, 0
	size_msg_open	equ	$-err_msg_open
	err_msg_arglen	db	"ERROR: Filename must be ", FILENAME_LIMIT + '0', " characters or less", 10, 0
	size_msg_arglen	equ	$-err_msg_arglen
	err_msg_ascii	db	"ERROR: Filename contains unprintable characters", 10, 0
	size_msg_ascii	equ	$-err_msg_ascii

section .text
	global _start


_start:

	mov ebp, esp		; esp is the arg count
	cmp dword [ebp], 1	; if no args (name of program only)
	je err_noargs		; print error message and quit
	
	; Set up first cmd line arg for validation
	mov esi, [ebp + 8]	; address of first arg

	; Make sure cmd line arg isn't too long
	call length_check

	; Copy addr to cmd line arg again, to undo inc
	mov esi, [ebp + 8]	; address of first arg

	; Make sure filename only contains printable ascii
	call ascii_check

	; Copy first cmd line arg to memory labeled filename
	mov esi, [ebp + 8]	; source addr for movsb
	mov edi, filename	; destination addr for movsb
	mov ecx, FILENAME_LIMIT	; number of bytes to copy
	rep movsb

	; Open file for reading and writing
	; Create if file does not exist
	mov eax, 5		; System call number for open
	mov ebx, filename	; Pointer to the filename

	; Perform bitwise or to combine args in assembly
	mov ecx, 0x2	; read/write - O_RDWR
	or ecx, 0x40	; create - O_CREAT
	or ecx, 0x400	; append - O_APPEND

	mov edx, 0644o
	int 0x80	; Call the kernel

    ; Check for errors in the open syscall (in eax)
	cmp eax, 0
	jl err_open

	; Else store file descriptor in memory
	mov [descriptor], eax

	; set initial filesize
	call setfilesize

	; Find program break
	mov eax, 45	; brk syscall
	mov ebx, 0	; get end of data segment
	int 0x80

	; Store address for initial program break in memory
	mov [progbreak], eax	

	; Increment program break address by filesize and set new break address
	mov eax, 45	; brk syscall
	mov ebx, [progbreak]
	add ebx, [filesize]
	int 0x80

	; Move break pointer to content pointer
	mov eax, [progbreak]
	mov [content], eax


loop:
	; Show marker designating user input
	mov edx, 2	; write 2 bytes
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
	; increment to check second byte of input
	inc ecx	; buffer left over from read syscall
	cmp byte [ecx], 10
	je command

	; else restart read input loop
	dec ecx		; reverse increment to restore ecx (necessary?)
	jmp loop	; loop not _start so we don't open the file again


command:
	; decrement to check first byte of input
	dec ecx

	; if a then append
	cmp byte [ecx], 97
	je append

	; if i then insert
	cmp byte [ecx], 105
	je insert 

	; else if p then print
	cmp byte [ecx], 112
	je print

	; else if q then quit
	cmp byte [ecx], 113
	je close_quit

	jmp loop


append:
	call appendinput
	jmp loop


insert:
	call readfile
	mov [filesize], eax	; save number of bytes read

	; delete file content
	; truncate open file descriptor to zero bytes
	mov eax, 93	; System call number for ftruncate
	mov ebx, [descriptor]
	mov ecx, 0 	; Set size to 0
	int 0x80	; Call the kernel

	; Check for errors in the syscall (in eax)
	cmp eax, 0
	jl close_quit_err 

	; Save old filesize for appending old content
	mov eax, [filesize]
	mov [oldfilesize], eax
	call appendinput

	; append old file contents
	mov edx, [oldfilesize] 
	mov eax, 4		; syscall number for write
	mov ebx, [descriptor]	; file descriptor for stdout
	mov ecx, [content]	; addr of dynamically allocated memory in heap
	int 0x80		; invoke the kernel

	call resetpointer
	call setfilesize
	jmp loop


print:
	call readfile

	; output the whole file
	mov edx, eax    	; write number of bytes read
	mov eax, 4		; syscall number for write
	mov ebx, 1		; file descriptor for stdout
	mov ecx, [content]	; addr to write to
	int 0x80		; invoke the kernel

	call resetpointer

	; Check for errors in the lseek syscall (in eax)
	cmp eax, 0
	jl close_quit_err

	jmp loop


;; close and quit

close_quit:
	call closefile
	mov eax, 1	; syscall number for exit
	xor ebx, ebx	; exit code 0
	int 0x80	; invoke the kernel

close_quit_err:
	call closefile
	mov eax, 1	; syscall number for exit
	mov ebx, 1	; exit code 1
	int 0x80	; invoke the kernel
	
quit_err:
	; File never opens, so don't close
	mov eax, 1	; syscall number for exit
	mov ebx, 1	; exit code 1
	int 0x80	; invoke the kernel


;; print error messages

err_noargs:
	mov eax, 4
	mov ebx, 1
	mov ecx, err_msg_noargs
	mov edx, size_msg_noargs
	int 0x80
	jmp quit_err

err_open:
	mov eax, 4
	mov ebx, 1
	mov ecx, err_msg_open
	mov edx, size_msg_open
	int 0x80
	jmp quit_err

err_arglen:
	mov eax, 4
	mov ebx, 1
	mov ecx, err_msg_arglen
	mov edx, size_msg_arglen
	int 0x80
	jmp quit_err

err_ascii:
	mov eax, 4
	mov ebx, 1
	mov ecx, err_msg_ascii
	mov edx, size_msg_ascii
	int 0x80
	jmp quit_err


;; functions

closefile:
	mov eax, 6	; close file
	mov ebx, [descriptor]
	int 0x80
	ret


readfile:
	call setfilesize
	mov eax, 3
	mov ebx, [descriptor]
	mov ecx, [content]
	mov edx, [filesize]
	int 0x80
	ret


readinput:
	; read user input
	mov eax, 3
	mov ebx, 0
	mov ecx, input
	mov edx, 80
	int 0x80
	ret


writeinput:
	; write one line of user input after calling readinput
	mov edx, eax    	; write number of bytes read
	mov eax, 4		; syscall number for write
	mov ebx, [descriptor]
	mov ecx, input		; variable to write
	int 0x80		; invoke the kernel
	ret


setfilesize:
	; Get new filesize using lseek syscall
	mov eax, 19       ; syscall number for lseek
	mov ebx, [descriptor]      ; file descriptor
	mov ecx, 0        ; offset
	mov edx, 2        ; SEEK_END
	int 0x80          ; make the system call

	; Save return value to memory
	mov [filesize], eax

	call resetpointer
	ret


resetpointer:
	; reset file pointer
	mov eax, 19           ; lseek system call number
	mov ebx, [descriptor] ; file descriptor
	mov ecx, 0            ; offset (seek from the beginning of the file)
	mov edx, 0            ; whence (SEEK_SET)
	int 0x80              ; invoke the kernel
	ret


length_check:
	; Validate filename cmd line arg does not exceed character limit
	; esi - address to unmodified filename argument copied from stack

	xor ecx, ecx	; use ecx as counter set to 0
	jmp .length	; don't advance until 1st char is compared

.count:
	inc esi	; advance to next char
	inc ecx	; count char
	
.length:
	; Get length of first cmd line arg
	cmp byte [esi], 0	; check if first char is zero byte (end of string)
	jne .count		; If not zero, start counting

	mov [argsize], ecx	; save length to memory

	; Exit if filename is too long
	cmp dword [argsize], FILENAME_LIMIT 
	jg err_arglen		; error if argsize > limit

	ret


ascii_check:
	; Validate filename cmd line arg only contains printable ascii
	; esi - address to unmodified filename arg copied from stack

.loop:
	cmp byte [esi], 0	; end of string
	je .done

	cmp byte [esi], 0x20	; compare against Space
	jl err_ascii		; error if below space

	cmp byte [esi], 0x7E	; compare against tilde
	jg err_ascii		; error if above tilde

	inc esi			; advance to next char
	jmp .loop		; repeat loop

.done:
	ret


appendinput:
.loop:
	call readinput

	; check for newline in second byte of input
	inc ecx		; buffer left over from read syscall
	cmp byte [ecx], 10
	je .command

.write:
	call writeinput
	call setfilesize
	jmp .loop	; keep appending

.command:
	; if . then stop appending
	dec ecx
	cmp byte [ecx], 46
	jne .write 
	ret

