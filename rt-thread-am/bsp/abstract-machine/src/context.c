#include <am.h>
#include <klib.h>
#include <rtthread.h>

static rt_ubase_t rt_interrupt_from_thread = 0;
static rt_ubase_t rt_interrupt_to_thread = 0;
static rt_uint32_t rt_thread_switch_interrupt_flag = 0;

static Context* ev_handler(Event e, Context *c) {
  switch (e.event) {
    case EVENT_YIELD:
      // 保存当前上下文到 from 线程
      if (rt_interrupt_from_thread != 0) {
        *(void **)rt_interrupt_from_thread = c;
      }
      // 切换到 to 线程的上下文
      if (rt_interrupt_to_thread != 0) {
        c = *(Context **)rt_interrupt_to_thread;
      }
      rt_thread_switch_interrupt_flag = 0;
      break;
    default: 
      printf("Unhandled event ID = %d\n", e.event); 
      assert(0);
  }
  return c;
}

void __am_cte_init() {
  cte_init(ev_handler);
}

// 汇编实现的上下文恢复函数
extern void __rt_hw_context_switch_to_asm(rt_ubase_t to);

void rt_hw_context_switch_to(rt_ubase_t to) {
  // to 是 &thread->sp，解引用获取 sp 值
  rt_interrupt_from_thread = 0;
  rt_interrupt_to_thread = to;
  rt_thread_switch_interrupt_flag = 1;
  
  // 使用 yield 触发切换
  yield();
  
  // 理论上不会执行到这里，因为 ev_handler 会返回新上下文
}

void rt_hw_context_switch(rt_ubase_t from, rt_ubase_t to) {
  // from 和 to 都是 &thread->sp
  if (rt_thread_switch_interrupt_flag != 1) {
    rt_thread_switch_interrupt_flag = 1;
    rt_interrupt_from_thread = from;
  }
  rt_interrupt_to_thread = to;
  
  yield();
}

void rt_hw_context_switch_interrupt(rt_ubase_t from, rt_ubase_t to, struct rt_thread *to_thread) {
  if (rt_thread_switch_interrupt_flag != 1) {
    rt_thread_switch_interrupt_flag = 1;
    rt_interrupt_from_thread = from;
  }
  rt_interrupt_to_thread = to;
}

rt_uint8_t *rt_hw_stack_init(void *tentry, void *parameter, rt_uint8_t *stack_addr, void *texit) {
  // 使用 AM 的 kcontext 创建上下文
  // stack_addr 是 (栈底 + 栈大小 - sizeof(rt_ubase_t))，即接近栈顶的位置
  // kcontext 会在 kstack.end - sizeof(Context) 处放置 Context
  Area kstack = {
    .start = (void *)(stack_addr - 16384),  // 栈底近似值，不需要精确
    .end = (void *)(stack_addr + sizeof(rt_ubase_t))  // 实际栈顶
  };
  
  Context *ctx = kcontext(kstack, (void (*)(void *))tentry, parameter);
  
  // 设置 texit 为线程退出函数（存储在某个通用寄存器中，如 ra）
  ctx->gpr[1] = (uintptr_t)texit;  // ra 寄存器
  
  return (rt_uint8_t *)ctx;
}
