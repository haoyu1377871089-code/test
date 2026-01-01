#include <am.h>
#include <riscv/riscv.h>
#include <klib.h>

static Context* (*user_handler)(Event, Context*) = NULL;

Context* __am_irq_handle(Context *c) {
  if (user_handler) {
    Event ev = {0};
    // 根据 mcause 识别异常类型
    // RISC-V: mcause 为异常号，ecall-from-M 为 11
    // AM 的 yield 使用 ecall 并在 a5 (RV32E) 传 -1
    switch (c->mcause) {
      case 11: // ecall from M-mode
        ev.event = EVENT_YIELD;
        ev.cause = c->mcause;
        break;
      default:
        ev.event = EVENT_ERROR;
        ev.cause = c->mcause;
        break;
    }

    c = user_handler(ev, c);
    assert(c != NULL);
  }

  return c;
}

extern void __am_asm_trap(void);

bool cte_init(Context*(*handler)(Event, Context*)) {
  // 初始化异常入口
  asm volatile("csrw mtvec, %0" : : "r"(__am_asm_trap));

  // 注册事件处理函数
  user_handler = handler;

  return true;
}

Context *kcontext(Area kstack, void (*entry)(void *), void *arg) {
  // 简单实现：暂不支持内核线程上下文
  return NULL;
}

void yield() {
  // RV32E 使用 a5 寄存器传递 -1
  asm volatile("li a5, -1; ecall");
}

bool ienabled() {
  // 简单实现：暂不支持真正的中断使能检查
  return false;
}

void iset(bool enable) {
  // 简单实现：暂不支持真正的中断使能控制
  // 如果需要可以操作 mstatus.MIE 位
}
