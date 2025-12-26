CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

CFLAGS = -march=rv32e -mabi=ilp32e -nostdlib -Wl,-Ttext=0x20000000

all: char-test.bin

char-test.elf: start.S main.c
	$(CC) $(CFLAGS) -o $@ $^

char-test.bin: char-test.elf
	$(OBJCOPY) -S -O binary $< $@

clean:
	rm -f *.elf *.bin