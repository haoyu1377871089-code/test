#!/bin/bash
RTL_FILES="/home/hy258/ysyx-workbench/ysyxSoC/build/ysyxSoCFull.v $(find /home/hy258/ysyx-workbench/ysyxSoC/perip -name "*.v") /home/hy258/ysyx-workbench/npc/vsrc/ysyx_00000000.v $(find /home/hy258/ysyx-workbench/npc/vsrc/core -name "*.v")"
make -C /home/hy258/ysyx-workbench-ref/yosys-sta sta \
  DESIGN=ysyxSoCFull \
  SDC_FILE=/home/hy258/ysyx-workbench/ysyxSoCFull.sdc \
  RTL_FILES="$RTL_FILES" \
  CLK_FREQ_MHZ=500
