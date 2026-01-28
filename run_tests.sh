#!/bin/bash
# 测试运行脚本
# 用于在每次修复后运行dummy和microbench测试

set -e

AM_HOME=${AM_HOME:-/workspace/abstract-machine}
ARCH=${ARCH:-riscv32e-ysyxsoc}
NPC_BUILD_DIR=${NPC_BUILD_DIR:-/workspace/npc/build_soc}
TEST_TIMEOUT=${TEST_TIMEOUT:-120}

echo "=========================================="
echo "Running tests for NPC Pipeline"
echo "=========================================="
echo "AM_HOME: $AM_HOME"
echo "ARCH: $ARCH"
echo "NPC_BUILD_DIR: $NPC_BUILD_DIR"
echo ""

# 构建dummy测试
echo "Building dummy test..."
cd /workspace/am-kernels/tests/cpu-tests
if [ ! -f Makefile.dummy ]; then
    echo "NAME = dummy" > Makefile.dummy
    echo "SRCS = tests/dummy.c" >> Makefile.dummy
    echo "include $AM_HOME/Makefile" >> Makefile.dummy
fi

ARCH=$ARCH make -f Makefile.dummy 2>&1 | tail -20

# 查找dummy二进制文件
DUMMY_BIN=$(find build -name "*dummy*.bin" 2>/dev/null | head -1)
if [ -z "$DUMMY_BIN" ]; then
    echo "ERROR: dummy binary not found!"
    exit 1
fi

echo "Found dummy binary: $DUMMY_BIN"

# 运行dummy测试
echo ""
echo "=========================================="
echo "Running dummy test..."
echo "=========================================="
cd /workspace

if [ -f "$NPC_BUILD_DIR/ysyxSoCFull" ]; then
    timeout $TEST_TIMEOUT "$NPC_BUILD_DIR/ysyxSoCFull" --no-nvboard -b "$DUMMY_BIN" 2>&1 | tee dummy_test.log
    
    if grep -q "PASS\|SUCCESS\|HIT GOOD TRAP" dummy_test.log 2>/dev/null; then
        echo ""
        echo "=========================================="
        echo "✓ DUMMY TEST PASSED"
        echo "=========================================="
        
        # 如果dummy成功，运行microbench
        echo ""
        echo "Building microbench..."
        cd /workspace/am-kernels/benchmarks
        # TODO: 构建microbench
        
        echo ""
        echo "=========================================="
        echo "Running microbench..."
        echo "=========================================="
        # TODO: 运行microbench
        
    else
        echo ""
        echo "=========================================="
        echo "✗ DUMMY TEST FAILED"
        echo "=========================================="
        exit 1
    fi
else
    echo "ERROR: ysyxSoCFull not found at $NPC_BUILD_DIR/ysyxSoCFull"
    echo "Please build the simulator first"
    exit 1
fi

echo ""
echo "=========================================="
echo "All tests completed"
echo "=========================================="
