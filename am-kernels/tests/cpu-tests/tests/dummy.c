#include <am.h>
#include <klib.h>
#include <klib-macros.h>

void putch(char ch);

int global_var = 42;

int main() {
  if (global_var == 42) putch('Y');
  else putch('N');
  
  global_var = 123;
  if (global_var == 123) putch('G');
  else putch('F');
  
  return 0;
}
