# Lab 9

*This lab starts with a typewriter program, then moves on to an edlin-style program. Both programs were written in assembly with help from ChatGPT, in order to test the strengths and weaknesses of AI-assisted programming.*

## typewriter

Use chatgpt to create an assembly program that reads user input and prints it back out when the enter key is pressed. Keep asking for input until enter is pressed on a blank line. I made my own changes to the code to make sure it writes the same number of bytes as were previously read. Otherwise, if the previously entered string is longer, there will be leftover characters in the input buffer. See `mov edx, eax` which copies the return value of the read syscall (number of bytes read) as the 3rd argument to the write syscall (number of bytes to write).

	section .bss
		; 552 is the max number of bytes according to `man read`
		input resb 552	; reserve 552 bytes

	section .text
		global _start

	_start:

		; File descriptor for stdin is 0
		mov eax, 3		; syscall number for read
		mov ebx, 0		; file descriptor for stdin
		mov ecx, input	; variable to store input
		mov edx, 552	; read 552 bytes
		int 0x80		; invoke the kernel

		; Exit if only a newline is entered
		cmp byte [ecx], 10
		je end

		mov edx, eax    ; get bytes read from syscall 3
		mov eax, 4		; syscall number for write
		mov ebx, 1		; file descriptor for stdout
		mov ecx, input	; variable to write

		int 0x80		; invoke the kernel

		jmp _start

	end:
		mov eax, 1		; syscall number for exit
		xor ebx, ebx	; exit code 0
		int 0x80		; invoke the kernel

Compile and run:

	$ make clean ; make && ./typewriter
	rm typewriter.o typewriter
	nasm -f elf32 typewriter.asm
	ld -m elf_i386 -o typewriter typewriter.o
	hello world
	hello world
	foobarbaz
	foobarbaz
	foo
	foo

Before I figured out how to use the number of bytes read to limit the number of bytes output to the screen, I tried to clear the input buffer. Chatgpt got me most of the way there, but it frequently used at least one wrong register for the given instruction. It eventually suggested the `rep stosb` command, which is explained correctly on stackoverflow:

> For ecx repetitions, stores the contents of eax into where edi points to

<https://stackoverflow.com/questions/3818856/what-does-the-rep-stos-x86-assembly-instruction-sequence-do>

We can use this instruction to write 552 zero-bytes to the address space occupied by our input buffer.

	;mov edx, eax   ; get bytes read from syscall 3
	mov edx, 552    ; write max number of bytes
	mov eax, 4		; syscall number for write
	mov ebx, 1		; file descriptor for stdout
	mov ecx, input	; variable to write

	int 0x80		; invoke the kernel

	; Clear the input buffer
	mov ecx, 552	; number of bytes for stosb to write
	mov edi, input	; pointer to input buffer
	xor eax, eax	; set eax to 0
	rep stosb		; for ecx reps, store eax to edi pointer

	jmp _start		; start the read/write loop over again

The behavior of the program will look the same as before when you run it. If you comment out the code that clears the input buffer, you will see how leftover characters break the output. The first line of incorrect output is `fff`. Then instead of outputting just `a`, it outputs `a`, then a newline, then `fff`.

	$ make clean ; make && ./typewriter
	rm typewriter.o typewriter
	nasm -f elf32 typewriter.asm
	ld -m elf_i386 -o typewriter typewriter.o
	ffffff
	ffffff
	cc
	cc
	fff
	a
	a

	fff

## edlin

Moving on--now create an edlin-style program that lets the user insert text at the top or bottom of a file. Hold off on using chatgpt until we need it. We can use almost the same code from our previous program to make a program that continuously reads input until a `q` is entered. This works by reading the first byte of input, so now we have a bug to fix; Any string starting with `q` will also quit the program. 

	section .bss
		input resb 80	; limit lines to 80 characters

	section .text
		global _start

	_start:

		; File descriptor for stdin is 0
		mov eax, 3		; syscall number for read
		mov ebx, 0		; file descriptor for stdin
		mov ecx, input	; variable to store input
		mov edx, 80		; read 80 bytes
		int 0x80		; invoke the kernel

		; Exit if q character is entered
		cmp byte [ecx], 113
		je end

		jmp _start

	end:
		mov eax, 1		; syscall number for exit
		xor ebx, ebx	; exit code 0
		int 0x80		; invoke the kernel

Let's quit on a `q` followed by a newline instead. Time to use chatgpt. It suggests ecx can be incremented before testing a byte, so that the 2nd byte is tested instead of the 1st. Instead of comparing the first byte against the `q` character, compare the second byte against a newline--because all valid commands are 1 character followed by a newline.

	;cmp byte [ecx], 113

	; Exit if 2nd byte is a newline
	inc ecx
	cmp byte [ecx], 10
	je end

Now that the program can recognize a command, do another compare to identify what command was entered. Test if the character is a `q` and quit if it is. We test the first byte by decrementing ecx after having incremented it to check the second byte for a newline.

		; If second char is newline, continue to command phase
		; else restart read input loop
		inc ecx
		cmp byte [ecx], 10
		je command
		jmp _start

	command:
		dec ecx
		cmp byte [ecx], 113
		je end
		jmp _start

Run it to demonstrate behavior. All lines starting at `hello` are input. Program exits after `q`.

	$ make clean; make && ./edlin
	rm edlin.o edlin
	nasm -f elf32 edlin.asm
	ld -m elf_i386 -o edlin edlin.o
	hello
	h
	quit
	q
	$ echo $?
	0

Pretty soon we'll be printing text, so let's add an input marker `>` to distinguish input from output.

	section .data
		marker db '> ', 0

	_start:

		; Show marker designating user input
		mov edx, 2		; write 2 bytes
		mov eax, 4
		mov ebx, 1
		mov ecx, marker
		int 0x80

### Read and print

To read from a file, we should be able to use the same read syscall with a different argument in ebx for the file descriptor (0 is stdin). Maybe chatgpt can tell us what number to use.

> Me: what args to pass to read syscall for reading file `out.txt`

> ChatGPT: To read from a file using the read syscall in NASM, you need to use file descriptors. First, you'll need to open the file using the open syscall, which returns a file descriptor. Then, you can use this file descriptor with the read syscall.

It gives us this code to open a file for reading and writing, then test if there was an error (like if the file does not exist). This works fine; the program keeps running when `out.txt` is present, and immediately quits if `out.txt` is missing. The new `jl` instruction jumps if return value is less than 0.

	_start:

		; Open file for reading and writing
		mov eax, 5               ; System call number for open
		mov ebx, filename        ; Pointer to the filename
		mov ecx, 1               ; Flags (O_RWONLY in this case)
		int 0x80                 ; Call the kernel

		; Check for errors in the open syscall (in eax)
		cmp eax, 0
		jl  end       ; quit if there was an error

Now we can output the contents of the file upon entering the print (`p`) command. Store the file descriptor in memory so it can be used to close the file later. Currently the open, read, print, and close sections will run sequentially, when the `p` command is entered. 

	section .bss
		input resb 80		; limit lines to 80 characters
		content resb 552	; file contents
		descriptor resb 4	; file descriptor

	section .data
		marker db '> ', 0
		filename db 'out.txt', 0

	; _start section omitted

	command:
		dec ecx

		; if p then print
		cmp byte [ecx], 112
		je open

		; else if q then quit
		cmp byte [ecx], 113
		je end

		jmp _start

	open:
		; Open file for reading and writing
		mov eax, 5			; System call number for open
		mov ebx, filename	; Pointer to the filename
		mov ecx, 2			; read and write
		int 0x80			; Call the kernel

		; Check for errors in the open syscall (in eax)
		cmp eax, 0
		jl  end		; quit if there was an error

		; Else store file descriptor in memory
		mov [descriptor], eax

	read:
		; Read from the file
		mov ebx, [descriptor]    ; File descriptor (from open syscall)
		mov eax, 3               ; System call number for read
		mov ecx, content         ; Buffer to read into
		mov edx, 552             ; Number of bytes to read (adjust as needed)
		int 0x80                 ; Call the kernel

	print:
		; output the whole file
		mov edx, eax    	; write number of bytes read
		mov eax, 4			; syscall number for write
		mov ebx, 1			; file descriptor for stdout
		mov ecx, content	; variable to write
		int 0x80			; invoke the kernel

	close:
		mov eax, 6
		mov ebx, [descriptor]
		int 0x80
		jmp _start

Run the code, with `out.txt` containing string "Hello world".

	$ make clean; make && ./edlin 
	rm edlin.o edlin
	nasm -f elf32 edlin.asm
	ld -m elf_i386 -o edlin edlin.o
	> foo
	> p
	Hello world
	> q

### Append user input

Now add another command `a` to append to the file. This step requires knowledge of bitwise flags and some constants which are not well documented. The source file `fnctl.h` with their definitions did not come up in search results either, or the values were wrong. I was lucky to find something on stack overflow that showed the octal values of `O_APPEND` and `O_RDWR`, which must be combined as a single argument and passed to the write syscall. Although we could probably perform a bitwise OR in assembly, I'm using python instead.

<https://stackoverflow.com/questions/48541868/how-to-append-to-a-file-using-x86-64-linux-system-calls>

	>>> 0x400 | 0x2
	1026

Now plug that value in to the assembly program. Open the file at the very beginning of `_start` and close it as part of `end`. 

	_start:
		; Open file for reading and writing
		mov eax, 5			; System call number for open
		mov ebx, filename	; Pointer to the filename
		mov ecx, 1026		; bitwise 0x2|0x400 (read/write, append)
		;mov edx, 0644
		int 0x80			; Call the kernel

Add a new `a` command for append:

	command:
		dec ecx

		; if a then append
		cmp byte [ecx], 97
		je append

Write the code to append a line to the file. We're duplicating code for the read syscall here, but we can clean that up later. Note that chatgpt gave a lot of wrong answers for how to open a file and append to it. It mentioned nothing about a bitwise OR, and instead tried to send the append flag on another register, as a separate argument.

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

Compile and run. The user can enter the `a` command, then enter one line of text, after which they are prompted for another command.

	$ make clean; make && ./edlin 
	rm edlin.o edlin
	nasm -f elf32 edlin.asm
	ld -m elf_i386 -o edlin edlin.o
	> p
	hi there
	> does nothing
	> p
	hi there
	> a
	line 2
	> p
	hi there
	line 2
	> a
	another one
	> p
	hi there
	line 2
	another one
	> q

<div style="page-break-after: always;"></div>

### File pointers

At this point I ran into a bug. Every time the program jumps to start, it reopens the file. You aren't supposed to do that. But when I created a main loop and jumped to that instead, the file would only write to the screen once, and subsequent print commands would fail. It took me a while to figure out that is because the file pointer needs to be reset. Chatgpt actually came up with the solution right away, once I asked it the right question.

> __Me:__ in order to keep writing the file contents to stdout, i have to keep re-opening the file. why?

> __ChatGPT:__  
> File Pointer Position:  
> When you open a file for reading or writing, the file pointer is positioned at the beginning of the file. Subsequent reads or writes will start from this position. After reading or writing the file, the file pointer is typically moved to the end of the read or written data.
> If you want to repeatedly read the entire file, you may need to reset the file pointer to the beginning of the file before each read operation. You can use the lseek system call to set the file offset to a specific position.

> __Me:__ how to use lseek to reset file pointer after writing?

It gave me this code that ran with no modification:

	; After writing the file
	mov eax, 19          ; lseek system call number
	mov ebx, [descriptor] ; file descriptor
	mov ecx, 0            ; offset (seek from the beginning of the file)
	mov edx, 0            ; whence (SEEK_SET)
	int 0x80              ; invoke the kernel

	; Check for errors in the lseek syscall (in eax)
	cmp eax, -1
	je  error_handling    ; handle error if needed

Now that we have that settled, modify the append section so that it loops and keeps appending until it encounters a period command. I'm using a new readinput function, because I ask for user input in 2 places and it's nice not having to copy the code. All it does is make a read syscall and return.

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

Uh oh, that's one more jump to `_start` we need to take care of. Again, when we jump to the main loop instead, the subsequent print statement fails. Find the right place to reset the file pointer. This time we're writing to the file instead of reading from it, but I guess the pointer still needs to be reset afterward. Let's make our pointer reset code into a function, since we're using it twice now. Here again is the code for append.

	append:
		call readinput

		; check for newline in second byte of input
		inc ecx		; buffer left over from read syscall
		cmp byte [ecx], 10

		; if . then stop appending
		dec ecx
		cmp byte [ecx], 46
		;je _start
		je loop

		; write one line at a time
		mov edx, eax    	; write number of bytes read
		mov eax, 4			; syscall number for write
		mov ebx, [descriptor]
		mov ecx, input		; variable to write
		int 0x80			; invoke the kernel

		call resetpointer

		jmp append		; keep appending

The program now behaves according to specification, with 2 exceptions; The append loop writes every line after it is entered instead of writing on quit, and there is no insert/prepend command. I think I'll leave the append loop as is. 

	$ make clean; make && ./edlin
	rm edlin.o edlin
	nasm -f elf32 edlin.asm
	ld -m elf_i386 -o edlin edlin.o
	> p
	hi there
	> a
	line 2
	line 3
	.
	> p
	hi there
	line 2
	line 3
	> q

### Insert (prepend) user input

A command to insert text at the top of the file will require opening the file with alternate args. Turning it into a function would not be a bad idea. We also have to open and close the file at the beginning and end of the append/insert loops, instead of doing it at the start and end of the program. 

Oh, nevermind. There is no prepend flag for the open syscall. You have to move the data around yourself. Copy the file contents, overwrite the file with new user input, then append the old content again. This would probably mean making the append loop generic so we can choose whether to append user input or append old content. The open syscall can stay the same, set to read/write/append. Something like this:

1. Open file at start of program
2. Check for insert command
3. Read contents of file into content buffer
4. Read user input into input buffer
4. Delete old file
5. Write one line of user input at a time
6. Append old file contents on encountering the dot command
7. Close file on quit

First fix another bug, in append this time. I forgot to test the first comparison that identifies a command, so any line that starts with a period will stop the append loop. Create a local `.command` section and jump to it if the comparison is equal. Also create a writeinput function.

	append:
		call readinput

		; check for newline in second byte of input
		inc ecx		; buffer left over from read syscall
		cmp byte [ecx], 10
		je .command

		call writeinput
		call resetpointer
		jmp append		; keep appending

		.command:
			; if . then stop appending
			dec ecx
			cmp byte [ecx], 46
			je loop

Now rewrite the append section again and turn it into a generic function that can be called from within a new `insert` section. Our insert command appends user input, but it also deletes the file contents first, and appends the old content after the added lines. We don't want to duplicate the append code inside of insert, so we call `appendinput` instead. Here's the function:

	appendinput:
		.loop:
			call readinput

			; check for newline in second byte of input
			inc ecx		; buffer left over from read syscall
			cmp byte [ecx], 10
			je .command

		.write:
			call writeinput
			call resetpointer
			jmp .loop		; keep appending

		.command:
			; if . then stop appending
			dec ecx
			cmp byte [ecx], 46
			jne .write 
			ret

And here is the function call:

	append:
		call appendinput
		jmp loop

Now including the append functionality in the insert command is easy. Chatgpt helped come up with the truncate syscall, but it did it wrong. I had to use ftruncate (syscall 93) on the file descriptor, instead of using truncate (92) on the filename.

	insert:
		call readfile
		mov [filesize], eax		; save number of bytes read

		; delete file content
		; truncate open file descriptor to zero bytes
		mov eax, 93       ; System call number for ftruncate
		mov ebx, [descriptor]
		mov ecx, 0        ; Set size to 0
		int 0x80          ; Call the kernel

		; Check for errors in the syscall (in eax)
		cmp eax, 0
		jl end

		call appendinput

		; append old file contents
		mov edx, [filesize] 
		mov eax, 4				; syscall number for write
		mov ebx, [descriptor]	; file descriptor for stdout
		mov ecx, content		; variable to write
		int 0x80				; invoke the kernel

		call resetpointer	; so the next print command works
		jmp loop

<div style="page-break-after: always;"></div>

### It works!

At this point I think the program does everything it's supposed to. Here it is in action.

	$ make clean; make && ./edlin
	rm edlin.o edlin
	nasm -f elf32 edlin.asm
	ld -m elf_i386 -o edlin edlin.o
	> p 
	first line
	> a 
	2nd line
	3rd line
	.   
	> p 
	first line
	2nd line
	3rd line
	> i
	line 1
	line 2
	.
	> p
	line 1
	line 2
	first line
	2nd line
	3rd line
	> q

	$ echo $?
	0

### File creation

We could also easily make it create an `out.txt` file if it doesn't exist. May as well. There's an int flag `0x40` that corresponds to `O_CREAT` and lets the open syscall create a file. Bitwise OR this flag with our previous flags (append and read/write). 

	>>> 64 | 1026
	1090

After being pressed, chatgpt revealed the correct format for passing file permissions (`0644o`) with an o at the end for octal. 

	; Open file for reading and writing
	mov eax, 5			; System call number for open
	mov ebx, filename	; Pointer to the filename
	;mov ecx, 1026		; bitwise 0x2|0x400 (read/write, append)
	mov ecx, 1090		; bitwise 0x2|0x400|0x40 (read/write, append, create)
	mov edx, 0644o
	int 0x80			; Call the kernel

Proof of file creation:

	$ rm out.txt 
	$ make clean; make && ./edlin 
	rm edlin.o edlin
	nasm -f elf32 edlin.asm
	ld -m elf_i386 -o edlin edlin.o
	> p
	> a
	new file
	.
	> p
	new file
	> q
	$ cat out.txt
	new file
	$ ls -l out.txt
	-rw-r--r-- 1 kevin697059 kevin697059 9 Nov 18 18:50 out.txt

### Simple error handling

There might be one more thing worth fixing. Currently, if there is an error the program jumps to `end` and exits with the same code 0 for success every time. The program should instead use exit code 1 if quitting due to any of the less-than comparisons against eax that check for failed syscalls.

Create a few different labels to exit the program in 3 cases (success, general failure, open syscall failure).

	end:
		; exit with code 0 for success
		call closefile
		mov eax, 1		; syscall number for exit
		xor ebx, ebx	; exit code 0
		int 0x80		; invoke the kernel

	error:
		; exit with code 1 for failure
		call closefile
		mov eax, 1		; syscall number for exit
		mov ebx, 1		; exit code 1
		int 0x80		; invoke the kernel
		
	open_error:
		; file didn't open so don't close it
		mov eax, 1		; syscall number for exit
		mov ebx, 1		; exit code 1
		int 0x80		; invoke the kernel

Jump to the label when eax is less than 0:

	; Check for errors in the open syscall (in eax)
	cmp eax, 0
	jl open_error

Test it by removing the file create flag from the open syscall, and deleting the file.

	mov ecx, 1026		; bitwise 0x2|0x400 (read/write, append)
	;mov ecx, 1090		; bitwise 0x2|0x400|0x40 (read/write, append, create)

	$ rm out.txt
	$ make clean; make && ./edlin
	rm edlin.o edlin
	nasm -f elf32 edlin.asm
	ld -m elf_i386 -o edlin edlin.o
	$ echo $?
	1

It turns out doing the bitwise OR in assembly is very easy. Instead of passing the resulting integer value 1090, I can calculate it like this. Chatgpt was down, but a regular search revealed the behavior of the OR instruction. The result of each bitwise OR is stored in ecx. 

	; Perform bitwise or in assembly
	mov ecx, 0x2	; read/write - O_RDWR
	or ecx, 0x40	; create - O_CREAT
	or ecx, 0x400	; append - O_APPEND

<div style="page-break-after: always;"></div>

### Command line arguments

New specification for the edlin app: The filename should be given on the command line, instead of hardcoded. Accepting command line arguments is built in to linux; They are pushed onto the stack every time you run a program. A very good explanation is given on this defunct forum:

<https://web.archive.org/web/20220211194547/https://www.dreamincode.net/forums/topic/285550-nasm-linux-getting-command-line-parameters/>

There's some code appended at the end of this document which I previously had no use for. Now that we have some data on the stack, there is reason to set up a stack frame so that we can access arguments with an offset from ebp. 

But first, change the filename from an initialized variable in the .data section to a reserved (uninitialized) variable in the .bss section. We have to define a byte size for the filename, which will dictate how long the filename can be. I don't know yet what will happen if a filename that is too big gets passed as an argument. We actually have the same problem for file size, or the length of the content in a file. If we can handle one we can handle the other. Keep the filename length small so it's easy to test for names that are too long.

	section .bss
		filename resb 12	; max length of filename

Here we grab the arg count off the top of the stack, and quit if the wrong number of args is given. `dword` compares 4 bytes, because that's the size of each item on the stack. Alternatively, you could move `[ebp]` to another 32-bit register and then do the comparison. 

	mov ebp, esp		; esp is the arg count
	cmp dword [ebp], 1	; if no args (name of program only)
	je err_noargs		; print error message and quit

Now copy the first command line argument, which is 2 items below the top of the stack. `movsb` is used to copy data from one location in memory to another. Up until now, we've only copied data to memory by using syscalls, and providing memory labels as arguments to those syscalls.

	; Copy first cmd line arg to memory labeled filename
	mov esi, [ebp + 8]	; source addr for movsb
	mov edi, filename	; destination addr for movsb
	mov ecx, 12         ; number of bytes to copy
	rep movsb
    
Here's what the stack looks like, starting from the top, when the above code runs:

1. Argument count [esp]
2. Address of program path
3. Address of first arg
    
After some testing, it's clear that if you write a number of bytes higher than the number you reserved in memory, part of the data within the next variable will be overwritten. It's all just consecutive memory. 

Our filename has a fixed limit, but file content could be any size. Setting a hard limit means files bigger than that limit will be truncated, and the program will still reserve all that memory for files that are much smaller. If I put the content label at the end of the data segment and then read a file, nothing appears to get overwritten. I can reserve 0 bytes for content then still read in a file and print it. 

	section .bss
		descriptor resb 4	; file descriptor
		filesize resb 4		; size of previous file contents
		progbreak resb 4	; address for end of data segment
		filename resb 7		; max length of filename
		input resb 80		; limit lines to 80 characters
		content resb 0
        
The limiting factor then exists in the read syscall, which must be told how many bytes to read.

### Remove filesize limit

ChatGPT gave me a template for using the lseek syscall to find the filesize before calling my readfile function. This way I can tell the read syscall how many bytes to read into memory, instead of fixing it at 552. It gave me the wrong value for the `SEEK_END` constant at 0, so I tried 1 and 2 instead. Integer value 2 worked and I got the file size back in eax. 

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

I found the previous set of bit flag constants on my local machine at `/usr/include/asm-generic/fcntl.h`, but `SEEK_END` is not in that file. Use find and grep to verify that 2 is actually the value for `SEEK_END`.

	$ find /usr/include -name "*.h" -exec grep -H 'define SEEK_END' '{}' \; 
	/usr/include/stdio.h:#define SEEK_END	2	/* Seek from end of file.  */

My lseek code works for the first call to readfile, but it breaks appending and inserting. Reserving more memory for content doesn't fix it. I think we must be reading the wrong number of bytes on subsequent calls to readfile. We have to call the setfilesize function in a few different places.

- Once at the `_start` of the program, to set the initial size
- Under the `insert` label, after old file content is appended
- In the `appendinput` function, where user input is appended

So we set a new file size every time we write to the file, and the readfile function expects a properly defined filesize. Actually, there's no reason not to update the filesize when reading as well. Some redundancy is good. 

	readfile:
		call setfilesize
		mov eax, 3
		mov ebx, [descriptor]
		mov ecx, content
		mov edx, [filesize]
		int 0x80
		ret

And now we have to keep track of the old filesize so that we can append the old file contents when inserting new lines at the top.

	; Save old filesize for appending old content
	mov eax, [filesize]
	mov [oldfilesize], eax
	call appendinput

	; append old file contents
	mov edx, [oldfilesize] 
	mov eax, 4				; syscall number for write
	mov ebx, [descriptor]	; file descriptor for stdout
	mov ecx, content		; variable to write
	int 0x80				; invoke the kernel

	call resetpointer
	call setfilesize
	jmp loop

<div style="page-break-after: always;"></div>

### Examine the heap

And still the file is being read into a content buffer with 0 bytes reserved. I wrote some code to expand the heap, but it seems I don't need it.

	; Find program break
	;mov eax, 45	; brk syscall
	;mov ebx, 0	; get end of data segment
	;int 0x80

	; Store address for initial program break in memory
	;mov [progbreak], eax	

	; Increment program break address by filesize and set new break address
	;mov eax, 45	; brk syscall
	;mov ebx, [progbreak]
	;add ebx, [filesize]
	;int 0x80

So the question is, why expand the heap? Clearly I'm not "dynamically allocating" memory in a meaningful way. In addition to expanding the available memory, I should be able to allocate that memory starting from any label in the data or bss segments; Not just the label at the end. 

More important is when the program will eventually run up against whatever default memory barriers exist. The stack and the heap grow towards one another, and will eventually overflow if the program does not manage its memory. We can examine the size of the heap and the stack in gdb.

	gef➤  b _start
	Breakpoint 1 at 0x8049000
	gef➤  run
	Starting program: /home/kevin697059/asm/gpt/edlin/edlin

	gef➤  info proc mappings
	process 1120657
	Mapped address spaces:

			Start Addr   End Addr       Size     Offset  Perms   objfile
			 0x8048000  0x804a000     0x2000        0x0  r-xp   /home/kevin697059/asm/gpt/edlin/edlin
			 0x804a000  0x804b000     0x1000     0x2000  rwxp   /home/kevin697059/asm/gpt/edlin/edlin
			0xf7ff8000 0xf7ffc000     0x4000        0x0  r--p   [vvar]
			0xf7ffc000 0xf7ffe000     0x2000        0x0  r-xp   [vdso]
			0xfffdd000 0xffffe000    0x21000        0x0  rwxp   [stack]

The stack is labeled, but we can infer (with chatgpt's help) that heap memory is the only other writeable address space in the list (Perms rwxp). The size of the heap is shown in hex. Convert it to an integer.

	$ echo 'ibase=16; 1000' | bc
	4096

That's 4096 bytes or 4KB. Not very much memory. If we want to load in a file bigger than 4KB without causing a buffer overflow, we should expand the heap. Note that the heap does not appear to shrink or expand automatically when written to. After my program loads the file (gdb breakpoint at readfile), the size of the heap is the same. 

### Expand the heap

Uncomment previously mentioned code using the brk syscall to expand the heap by the filesize.

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

After the code runs there is a new entry in the output of `info proc mappings`. Whatever the original 4KB memory space was, gdb has decided to label this new one the heap.

	 0x804a000  0x804b000     0x1000     0x2000  rwxp   /home/kevin697059/asm/gpt/edlin/edlin
	 0x804b000  0x804c000     0x1000        0x0  rwxp   [heap]

It didn't expand the heap by the filesize. The new program break was supposed to be at address 0x804b09d (The original program break 0x804b000 plus the filesize). Instead the heap was expanded by 4KB to accommodate the file. That's nice, because I was worried I would have to set up memory pages myself. The OS knows better and just adds a new 4KB page instead of the exact number of bytes requested.

So now we just have to put checks in place to make sure the remaining fixed limits (for filename and line length) are respected. And maybe sanitize user input by limiting it to ascii characters. 

### Check length of argument

Another bug; I wrote the code to check for filename length, to make sure the command line argument is not bigger than the defined filename length limit. My code looks for a zero byte and stops counting the characters when it finds one. Maybe there is no zero byte at the end of an arg, because the program increments its way through the entire stack and counts every character until it finds one.

        ; Set up first cmd line arg for validation
        mov esi, [ebp + 8]	; address of first arg
        xor ecx, ecx		; use ecx as counter set to 0
        
    length:
        ; Validate length of first cmd line arg
        cmp byte [esi], 0		; check if char is zero byte (end of string)
        inc esi				; check next char
        inc ecx				; count char
        jne length			; loop if zero byte not reached
        mov [argsize], ecx	; save length to memory

Gdb shows that `esi` originally contains my filename "out.txt" which is successfully incremented 7 chars until it becomes an empty string. Then on next increment, esi reads: "SHELL=/bin/bash", which is clearly the previous item on the stack. It continues to loop through that string.  

And yet, gdb shows there *is* a null byte at the end of my arg...

	gef➤  x/8xb $esi
	0xffffd2cb:     0x6f    0x75    0x74    0x2e    0x74    0x78    0x74    0x00
	gef➤  x/s $esi
	0xffffd2cb:     "out.txt"

So my comparison must be wrong. ChatGPT thinks it's right, and it looks right to me, but the loop never ends. 

Ok, the code is working now. I guessed that conditional jumps can only happen immediately after a comparison, and rewrote my code like this:

	jmp length

	count:
		inc esi				; advance to next char
		inc ecx				; count char
		
	length:
		; Get length of first cmd line arg
		cmp byte [esi], 0	; check if first char is zero byte (end of string)
		jne count

		mov [argsize], ecx	; save length to memory

		; Exit if filename is too long
		cmp dword [argsize], FILENAME_LIMIT 
		jg quit_err

It quits on a filename arg that is one or more characters too long, and it opens the file otherwise. The inc instructions get their own label so that they can be skipped with a jmp before the first iteration of `length`. That way we are looking at the first byte of esi on the first comparison.

### Truncated files (more about the heap)

Side note--The heap does actually expand when my filesize grows. I tested a 13KB file and the heap now reads 0x3000 or 3 pages at 4KB each. That's 12KB plus the 4KB that's allocated by default.

	Start Addr   End Addr       Size     Offset  Perms   objfile
	 0x804a000  0x804b000     0x1000     0x2000  rwxp   /home/kevin697059/asm/gpt/edlin/edlin
	 0x804b000  0x804e000     0x3000        0x0  rwxp   [heap]

Lets apply the same logic we used to check the filename argument length, and write a check for line length when editing the file. 

But do we need to? If we didn't validate filenames, a user would input a too-long name and the program would truncate it, then start writing to the truncated file. That was bad, because it could overwrite something important that happened to match the truncated name. And it's just unexpected behavior. 

But maybe it's fine if lines get truncated before being appended to the file. Printing an error and quitting would not be a good alternative. So nevermind, let's leave it alone.

Also, there is a bug when printing large files to the screen (currently 13KB).

	lorem ipsum dolar set
	lorem ipsum dolar set
	lorem ipsum dol>

Let's see if filesize is being set properly. My output file is currently 29 bytes.

	$ du -b out.txt
	29      out.txt

Filesize looks good! It continues to read 29 all the way up until it writes to stdout.

	gef➤  x/d &filesize
	0x804a088 <filesize>:   29

One limit I might be running up against is the 32-bit registers and my equivalent 4-byte filesize variable. Is the number of bytes representing filesize bigger than the number which can fit in a 32-bit register? 

	$ du -b out.bak
	8384    out.bak

No, definitely not. There is that content variable though. I didn't reserve any space for it, because it was at the end of the heap and it seemed to do its job regardless. What if I give it 8384 bytes to accommodate the big file?

	content resb 8384

All better. The whole file prints.

	lorem ipsum dolar set
	lorem ipsum dolar set
	new line?
	> q

So the question is, how can we dynamically allocate content? And why isn't it enough to expand the heap by the filesize? Here's what the heap looks like when 8384 bytes are reserved for content.

	 0x804a000  0x804b000     0x1000     0x2000  rwxp   /home/kevin697059/asm/gpt/edlin/edlin
	 0x804b000  0x804d000     0x2000        0x0  rwxp   [heap]
	 0x804d000  0x8050000     0x3000        0x0  rwxp   [heap]

And here it is with 0 bytes reserved for content.

	 0x804a000  0x804b000     0x1000     0x2000  rwxp   /home/kevin697059/asm/gpt/edlin/edlin
	 0x804b000  0x804e000     0x3000        0x0  rwxp   [heap]

So we get an extra 2 pages or 8KB, which is about the size of our file. It looks like that 8KB is being reserved to accommodate the content var, then our manual adjustment of the heap is adding 12KB like before. Seeing as 12 > 8, why wasn't the existing heap big enough to accommodate our file? 

If I comment out all my code that expands the heap using brk, behavior is identical. So I guess I didn't test that very well. The code *did* create a heap entry in gdb, which goes away when the code is commented out. But it didn't increase whatever default limit is placed on the content var.

It's starting to look like the .bss and .data segments aren't actually part of the heap at all, and dynamic allocation for variables in the data segment is impossible. Maybe instead my content var should be a pointer, which points to dynamically allocated memory in the heap. 

<div style="page-break-after: always;"></div>

### Successful write to new heap memory

I made content a pointer and assigned it the value of progbreak, after expanding the heap like I was already doing using brk. Then I changed all 3 references to content so they use the address at `[content]` instead. My big file now outputs in its entirety, using the print command.

	; Increment program break address by filesize and set new break address
	mov eax, 45	; brk syscall
	mov ebx, [progbreak]
	add ebx, [filesize]
	int 0x80

	; Move break pointer to content pointer
	mov eax, [progbreak]
	mov [content], eax

Output:

	lorem ipsum dolar set
	lorem ipsum dolar set
	new line?
	another one?
	>

### Validate ascii in filename

Limit user input to a range of ascii characters. Use the same logic as checking for argument length. If current char is 0, we reached the end of the string. Otherwise, check if char is below Space or above `~` in the ascii table, and error out if it is. Put this code in an `ascii_check` function.

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

Also put the previous arg length validation code in a function. Here's where we call both functions, before writing the filename to memory.

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

The `ascii_check` function was tested by modifying the comparison against `~` to `y`, and passing a file named `z`.

	$ make clean ; make && ./edlin z
	rm edlin.o edlin
	nasm -f elf32 -g edlin.asm
	ld -m elf_i386 -o edlin edlin.o
	ERROR: Filename contains unprintable characters

### Conclusion

Our program may be useless, but it won't break easily. The user will not run up against arbitrary filesize limits, and if they do something wrong the program will quit and print an error (we hope). It is structured in a way that resembles something a person might write in a real programming language; There are functions, variables, and constants. Since there are no more bugs I can find, it looks like we're done.

---

## (unused) bonus code

*At one point I thought it was a good idea to create generic wrapper functions around syscalls. In practice, pushing args on the stack and calling a wrapper function is not any more convenient than just writing the syscall. But here's how I did it.* 

According to chatgpt, there is no keyword needed for defining a function. Just attach a label to some instructions and return at the end. Calling the function should push the return address onto the stack. In the example below, I am able to replace 3 uses of the read syscall with a function that reads 3 arguments from the stack. Calling the read function still requires 4 lines of code, but the first 3 are all push instructions (which are a little easier to read) and we no longer have to worry about copy/pasting blocks of code. We can be sure that all reads are the same, because the same code runs every time the program calls it.  

Chatgpt was able to help with very specific questions here. It showed me the syntax to access a value offset from ebp (`[ebp + 8]`), and that I have to move the contents of a variable or buffer to a register before pushing it on the stack. Remember to push args in reverse order (arg3, arg2, arg1).

First read call:

	append:
		; read 80 chars of input for one line
		push 80
		push input
		push 0
		call read

Second read call:

	print:
		push 552
		push content
		mov eax, [descriptor]	; can't push onto stack directly
		push eax
		call read

Third read call:

	; read first level of user input
	push 80
	push input
	push 0
	call read

This is the read function. It backs up ebp and replaces it with esp to set up a stack frame (a segment of the stack) so that we can access args that were pushed to the stack before calling the function. We get the args by accessing the value stored at predictable offsets from ebp (the base pointer), and move them into the appropriate registers for the read syscall. Then we restore the stack and pop off the backup of ebp. 

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

We could alternatively access args at an offset from esp and avoid setting up a stack frame; But using ebp is standard because it allows pushing new things onto the stack inside of our function. Remember that pushing onto the stack moves esp forward, so relying on a fixed offset from esp is a bad idea.

