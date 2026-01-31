CROSS_COMPILE := riscv64-linux-gnu-
# 使用 -nostdlib -ffreestanding 避免依赖系统头文件
COMMON_CFLAGS := -fno-pic -march=rv64g -mcmodel=medany -mstrict-align -ffreestanding -nostdlib
CFLAGS        += $(COMMON_CFLAGS) -static -nostdinc \
                 -I$(AM_HOME)/klib/include \
                 -isystem /usr/lib/gcc-cross/riscv64-linux-gnu/11/include \
                 -isystem /usr/riscv64-linux-gnu/include
ASFLAGS       += $(COMMON_CFLAGS) -O0
LDFLAGS       += -melf64lriscv -nostdlib

# overwrite ARCH_H defined in $(AM_HOME)/Makefile
ARCH_H := arch/riscv.h
