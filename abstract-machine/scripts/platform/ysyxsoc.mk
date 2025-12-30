AM_SRCS := platform/ysyxsoc/trm.c \
           platform/ysyxsoc/ioe/ioe.c \
           platform/ysyxsoc/spi.c

CFLAGS    += -fdata-sections -ffunction-sections
LDSCRIPTS += $(AM_HOME)/scripts/linker_ysyxsoc.ld
LDFLAGS   += --gc-sections -e _start

$(IMAGE).bin: $(IMAGE).elf
	@$(OBJCOPY) -S -j .text -j .rodata -j .data -O binary $< $@

image: $(IMAGE).bin

NPC_SOC_BIN = $(NPC_HOME)/build_soc/ysyxSoCFull

# FLASH_PROG: 可选的 Flash 程序，会被加载到 Flash 的 2MB 偏移处
run: image
ifdef FLASH_PROG
	$(NPC_SOC_BIN) $(IMAGE).bin $(FLASH_PROG)
else
	$(NPC_SOC_BIN) $(IMAGE).bin
endif