# RISC-V 32E 异常/中断入口 (trap handler)
# 适配 ysyxsoc 平台

#define concat_temp(x, y) x ## y
#define concat(x, y) concat_temp(x, y)
#define MAP(c, f) c(f)

#define LOAD  lw
#define STORE sw
#define XLEN  4

# RV32E 只有 16 个寄存器 (x0-x15)
#define REGS_LO16(f) \
      f( 1)       f( 3) f( 4) f( 5) f( 6) f( 7) f( 8) f( 9) \
f(10) f(11) f(12) f(13) f(14) f(15)

#define REGS(f) REGS_LO16(f)
#define NR_REGS 16

#define PUSH(n) STORE concat(x, n), (n * XLEN)(sp);
#define POP(n)  LOAD  concat(x, n), (n * XLEN)(sp);

# Context 结构大小：16 个 GPR + mcause + mstatus + mepc = 19 * 4 = 76 bytes
#define CONTEXT_SIZE  ((NR_REGS + 3) * XLEN)
#define OFFSET_SP     ( 2 * XLEN)
#define OFFSET_CAUSE  ((NR_REGS + 0) * XLEN)
#define OFFSET_STATUS ((NR_REGS + 1) * XLEN)
#define OFFSET_EPC    ((NR_REGS + 2) * XLEN)

.align 3
.globl __am_asm_trap
__am_asm_trap:
  # 分配上下文保存空间
  addi sp, sp, -CONTEXT_SIZE

  # 保存通用寄存器 (x1, x3-x15)
  MAP(REGS, PUSH)

  # 保存 CSR 寄存器
  csrr t0, mcause
  csrr t1, mstatus
  csrr t2, mepc

  STORE t0, OFFSET_CAUSE(sp)
  STORE t1, OFFSET_STATUS(sp)
  STORE t2, OFFSET_EPC(sp)


  # ecall 保存的是当前指令地址，返回时需要跳过 ecall (+4)
  csrr a0, mcause
  li   a1, 11           # ecall from M-mode
  bne  a0, a1, 2f       # 如果不是 ecall，跳过 +4
  addi t2, t2, 4
  STORE t2, OFFSET_EPC(sp)
2:

  # 调用 C 语言处理函数
  mv a0, sp
  call __am_irq_handle

  # 恢复 CSR 寄存器
  LOAD t1, OFFSET_STATUS(sp)
  LOAD t2, OFFSET_EPC(sp)
  csrw mstatus, t1
  csrw mepc, t2

  # 恢复通用寄存器
  MAP(REGS, POP)

  # 释放上下文空间
  addi sp, sp, CONTEXT_SIZE
  
  # 返回
  mret
