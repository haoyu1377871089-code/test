include $(AM_HOME)/scripts/platform/ysyxsoc.mk

# 使用裸机工具链，因为 ilp32e ABI 不被 Linux glibc 支持
CROSS_COMPILE := riscv64-unknown-elf-

# 注意：不要 include riscv.mk，因为它设置了 -melf64lriscv，对 rv32e 不正确
# 直接设置 rv32e 需要的编译和链接选项
ARCH_H := arch/riscv.h
CFLAGS  += -DISA_H=\"riscv/riscv.h\"
COMMON_CFLAGS := -fno-pic -march=rv32e_zicsr_zifencei -mabi=ilp32e -mcmodel=medany -mstrict-align
CFLAGS        += $(COMMON_CFLAGS) -static
ASFLAGS       += $(COMMON_CFLAGS) -O0
LDFLAGS       += -melf32lriscv
CFLAGS        += -I$(AM_HOME)/am/src/riscv/ysyxsoc/include

# 选择启动代码：
# SRAM_RUN=1  - 代码加载到 SRAM 执行（适合小程序，最快）
# PSRAM_RUN=1 - 代码加载到 PSRAM 执行，栈在 SRAM（适合大程序）
# 默认       - 代码在 Flash XIP 执行
ifdef SRAM_RUN
AM_SRCS += riscv/ysyxsoc/start_sram.S
else ifdef PSRAM_RUN
AM_SRCS += riscv/ysyxsoc/start_psram.S
else
AM_SRCS += riscv/ysyxsoc/start.S
endif

AM_SRCS += riscv/ysyxsoc/libgcc/div.S \
           riscv/ysyxsoc/libgcc/muldi3.S \
           riscv/ysyxsoc/libgcc/multi3.c \
           riscv/ysyxsoc/libgcc/ashldi3.c \
           riscv/ysyxsoc/libgcc/unused.c \
           riscv/ysyxsoc/cte.c \
           riscv/ysyxsoc/trap.S
