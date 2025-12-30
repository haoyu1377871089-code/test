.section .text
.global _start
_start:
  li sp, 0x0f001f00  # 初始化栈指针到 SRAM 末尾附近
  call c_main        # 跳转到 C 代码
  ebreak             # 如果返回，则停机
