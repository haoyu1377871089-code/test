AM_SRCS := platform/ysyxsoc/trm.c \
           platform/ysyxsoc/ioe/ioe.c

CFLAGS    += -fdata-sections -ffunction-sections
LDSCRIPTS += $(AM_HOME)/scripts/linker_ysyxsoc.ld
LDFLAGS   += --gc-sections -e _start

$(IMAGE).bin: $(IMAGE).elf
	@$(OBJCOPY) -S -O binary --gap-fill 0xff $< $@

image: $(IMAGE).bin

