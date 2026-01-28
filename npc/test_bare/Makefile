# Makefile - 裸机测试构建
CROSS_COMPILE := riscv64-unknown-elf-
AS := $(CROSS_COMPILE)gcc
LD := $(CROSS_COMPILE)ld
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump

ASFLAGS := -march=rv32e -mabi=ilp32e -nostdlib
LDFLAGS := -T bare.ld -melf32lriscv

# 所有测试
TESTS := bare_test lsu_test

all: $(addsuffix .bin, $(TESTS))

%.o: %.S
	$(AS) $(ASFLAGS) -c -o $@ $<

%.elf: %.o bare.ld
	$(LD) $(LDFLAGS) -o $@ $<

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.dis: %.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -f *.o *.elf *.bin *.dis

.PHONY: all clean
