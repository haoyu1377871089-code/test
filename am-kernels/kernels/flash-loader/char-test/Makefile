CC = riscv64-linux-gnu-gcc
OBJCOPY = riscv64-linux-gnu-objcopy
OBJDUMP = riscv64-linux-gnu-objdump

# char-test 将被加载到 SRAM 地址 0x0f000800 执行
CFLAGS = -march=rv32e -mabi=ilp32e -nostdlib -O2 -T linker.ld

all: char-test.bin

char-test.elf: start.S main.c linker.ld
	$(CC) $(CFLAGS) -o $@ start.S main.c

char-test.bin: char-test.elf
	$(OBJCOPY) -S -O binary $< $@
	$(OBJDUMP) -d $< > char-test.dis
	@echo "char-test.bin size: $$(stat -c%s $@) bytes"

clean:
	rm -f *.elf *.bin *.dis

.PHONY: all clean
