CC = riscv64-linux-gnu-gcc
OBJCOPY = riscv64-linux-gnu-objcopy
OBJDUMP = riscv64-linux-gnu-objdump

# 默认: char-test 将被加载到 SRAM 地址 0x0f000800 执行
# XIP: char-test 将在 Flash XIP 地址 0x30200000 执行
CFLAGS = -march=rv32e -mabi=ilp32e -nostdlib -O2

all: char-test.bin char-test-xip.bin

# SRAM 版本 (加载到 SRAM 执行)
char-test.elf: start.S main.c linker.ld
	$(CC) $(CFLAGS) -T linker.ld -o $@ start.S main.c

char-test.bin: char-test.elf
	$(OBJCOPY) -S -O binary $< $@
	$(OBJDUMP) -d $< > char-test.dis
	@echo "char-test.bin (SRAM) size: $$(stat -c%s $@) bytes"

# XIP 版本 (在 Flash 中就地执行)
char-test-xip.elf: start.S main_xip.c linker_xip.ld
	$(CC) $(CFLAGS) -T linker_xip.ld -o $@ start.S main_xip.c

char-test-xip.bin: char-test-xip.elf
	$(OBJCOPY) -S -O binary $< $@
	$(OBJDUMP) -d $< > char-test-xip.dis
	@echo "char-test-xip.bin (XIP) size: $$(stat -c%s $@) bytes"

clean:
	rm -f *.elf *.bin *.dis

.PHONY: all clean
