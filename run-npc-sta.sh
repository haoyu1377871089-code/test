#!/bin/bash
RTL_FILES="/home/hy258/ysyx-workbench/npc/vsrc/ysyx_00000000.v $(find /home/hy258/ysyx-workbench/npc/vsrc/core -name "*.v" | tr '\n' ' ')"
INCLUDE_DIRS="/home/hy258/ysyx-workbench/npc/vsrc/core"
make -C /home/hy258/ysyx-workbench-ref/yosys-sta sta \
  DESIGN=ysyx_00000000 \
  SDC_FILE=/home/hy258/ysyx-workbench/npc.sdc \
  RTL_FILES="$RTL_FILES" \
  VERILOG_INCLUDE_DIRS="$INCLUDE_DIRS" \
  CLK_FREQ_MHZ=500