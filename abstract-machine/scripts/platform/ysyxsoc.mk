AM_SRCS := platform/ysyxsoc/trm.c \
           platform/ysyxsoc/ioe/ioe.c \
           platform/ysyxsoc/spi.c

CFLAGS    += -fdata-sections -ffunction-sections
LDSCRIPTS += $(AM_HOME)/scripts/linker_ysyxsoc.ld
LDFLAGS   += --gc-sections -e _start

# MAINARGS 支持：将参数嵌入到二进制文件中
MAINARGS_MAX_LEN = 64
MAINARGS_PLACEHOLDER = the_insert-arg_rule_in_Makefile_will_insert_mainargs_here
CFLAGS += -DMAINARGS_MAX_LEN=$(MAINARGS_MAX_LEN) -DMAINARGS_PLACEHOLDER=$(MAINARGS_PLACEHOLDER)

$(IMAGE).bin: $(IMAGE).elf
	@$(OBJCOPY) -S -j .text -j .rodata -j .data -O binary $< $@
	@python $(AM_HOME)/tools/insert-arg.py $@ $(MAINARGS_MAX_LEN) $(MAINARGS_PLACEHOLDER) "$(mainargs)"

image: $(IMAGE).bin

NPC_SOC_BIN = $(NPC_HOME)/build_soc/ysyxSoCFull

# FLASH_PROG: 可选的 Flash 程序，会被加载到 Flash 的 2MB 偏移处
run: image
ifdef FLASH_PROG
	$(NPC_SOC_BIN) $(IMAGE).bin $(FLASH_PROG)
else
	$(NPC_SOC_BIN) $(IMAGE).bin
endif