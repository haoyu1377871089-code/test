AM_SRCS := platform/ysyxsoc/trm.c \
           platform/ysyxsoc/ioe/ioe.c

CFLAGS    += -fdata-sections -ffunction-sections
LDSCRIPTS += $(AM_HOME)/scripts/linker_ysyxsoc.ld
LDFLAGS   += --gc-sections -e _start

$(IMAGE).bin: $(IMAGE).elf
	@$(OBJCOPY) -S -j .text -j .rodata -j .data -O binary $< $@

image: $(IMAGE).bin

NPC_SOC_BIN = $(NPC_HOME)/build_soc/ysyxSoCFull

run: image
	$(NPC_SOC_BIN) $(IMAGE).bin