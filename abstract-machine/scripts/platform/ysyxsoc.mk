AM_SRCS := platform/ysyxsoc/trm.c \
           platform/ysyxsoc/ioe/ioe.c \
           platform/ysyxsoc/spi.c

CFLAGS    += -fdata-sections -ffunction-sections
LDFLAGS   += --gc-sections -e _start

# 选择链接脚本：
# SRAM_RUN=1  - 代码在 SRAM 中运行
# PSRAM_RUN=1 - 代码在 PSRAM 中运行，栈在 SRAM
# 默认       - 代码在 Flash XIP 中运行
ifdef SRAM_RUN
LDSCRIPTS += $(AM_HOME)/scripts/linker_ysyxsoc_sram.ld
else ifdef PSRAM_RUN
LDSCRIPTS += $(AM_HOME)/scripts/linker_ysyxsoc_psram.ld
else
LDSCRIPTS += $(AM_HOME)/scripts/linker_ysyxsoc.ld
endif

# MAINARGS 支持：将参数嵌入到二进制文件中
MAINARGS_MAX_LEN = 64
MAINARGS_PLACEHOLDER = the_insert-arg_rule_in_Makefile_will_insert_mainargs_here
CFLAGS += -DMAINARGS_MAX_LEN=$(MAINARGS_MAX_LEN) -DMAINARGS_PLACEHOLDER=$(MAINARGS_PLACEHOLDER)

# SRAM_RUN 或 PSRAM_RUN 模式需要包含 boot 段
ifneq ($(SRAM_RUN)$(PSRAM_RUN),)
$(IMAGE).bin: $(IMAGE).elf
	@$(OBJCOPY) -S -j .boot -j .text -j .rodata -j .data -O binary $< $@
	@python $(AM_HOME)/tools/insert-arg.py $@ $(MAINARGS_MAX_LEN) $(MAINARGS_PLACEHOLDER) "$(mainargs)"
else
$(IMAGE).bin: $(IMAGE).elf
	@$(OBJCOPY) -S -j .text -j .rodata -j .data -O binary $< $@
	@python $(AM_HOME)/tools/insert-arg.py $@ $(MAINARGS_MAX_LEN) $(MAINARGS_PLACEHOLDER) "$(mainargs)"
endif

image: $(IMAGE).bin

NPC_SOC_BIN = $(NPC_HOME)/build_soc/ysyxSoCFull

# FLASH_PROG: 可选的 Flash 程序，会被加载到 Flash 的 2MB 偏移处
run: image
ifdef FLASH_PROG
	$(NPC_SOC_BIN) $(IMAGE).bin $(FLASH_PROG)
else
	$(NPC_SOC_BIN) $(IMAGE).bin
endif