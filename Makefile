edlin: edlin.o
	ld -m elf_i386 -o edlin edlin.o

edlin.o: edlin.asm
	nasm -f elf32 -g edlin.asm

clean:
	rm edlin.o edlin
