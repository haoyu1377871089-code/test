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
  Context *c = (Context*)((char*)kstack.end - sizeof(Context));
  c->mepc = (uintptr_t)entry;
  c->gpr[10] = (uintptr_t)arg;  // a0 register
  c->gpr[2] = (uintptr_t)c;     // sp register
  c->mcause = 0;
  c->mstatus = 0;
  c->pdir = NULL;
  return c;
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

// MPE (多处理器扩展) 空实现
bool mpe_init(void (*entry)()) {
  return false;  // 不支持多处理器
}

int cpu_count() {
  return 1;  // 只有一个 CPU
}

int cpu_current() {
  return 0;  // 返回 CPU 0
}

int atomic_xchg(int *addr, int newval) {
  int oldval = *addr;
  *addr = newval;
  return oldval;
}

// VME (虚拟内存扩展) 空实现
bool vme_init(void* (*pgalloc)(int), void (*pgfree)(void*)) {
  return false;  // 不支持虚拟内存
}

void protect(AddrSpace *as) {
  // 空实现
}

void unprotect(AddrSpace *as) {
  // 空实现
}

void map(AddrSpace *as, void *va, void *pa, int prot) {
  // 空实现
}

Context *ucontext(AddrSpace *as, Area kstack, void *entry) {
  return NULL;  // 不支持用户态上下文
}
