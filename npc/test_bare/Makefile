# Makefile - 裸机测试构建
CROSS_COMPILE := riscv64-unknown-elf-
AS := $(CROSS_COMPILE)gcc
LD := $(CROSS_COMPILE)ld
OBJCOPY := $(CROSS_COMPILE)objcopy

ASFLAGS := -march=rv32e -mabi=ilp32e -nostdlib
LDFLAGS := -T bare.ld -melf32lriscv

all: bare_test.bin

bare_test.o: bare_test.S
	$(AS) $(ASFLAGS) -c -o $@ $<

bare_test.elf: bare_test.o bare.ld
	$(LD) $(LDFLAGS) -o $@ bare_test.o

bare_test.bin: bare_test.elf
	$(OBJCOPY) -O binary $< $@

clean:
	rm -f *.o *.elf *.bin

.PHONY: all clean
