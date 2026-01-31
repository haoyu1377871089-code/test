TOPNAME = top
# 头文件名称
NXDC_FILES = constr/top.nxdc
INC_PATH ?= $(abspath ./vsrc/npc_soc)
IMG ?=
# 定义一个可选的头文件搜索变量
GTKWAVE      ?= gtkwave         

VERILATOR = verilator
VERILATOR_CFLAGS += -MMD --build -cc  \
                -O3 --x-assign fast --x-initial fast --noassert \
                +define+SIMULATION

# 禁用VCD波形生成以节省磁盘空间（用于主频评估）
VERILATOR_CFLAGS_NO_TRACE = -MMD --build -cc  \
                -O3 --x-assign fast --x-initial fast --noassert \
                +define+SIMULATION

BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

default: $(BIN)

all: $(BIN)

$(shell mkdir -p $(BUILD_DIR))

# rules for NVBoard
include $(NVBOARD_HOME)/scripts/nvboard.mk
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
# 把 build/auto_bind.cpp 的绝对路径保存在 SRC_AUTO_BIND 中
$(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

# project source (npc_soc configuration)
VSRCS = $(shell find $(abspath ./vsrc/npc_soc) -name "*.v")
# C++ 源文件：npc_soc 专用 + 公共模块
CSRCS = $(shell find $(abspath ./csrc/npc_soc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
CSRCS += $(shell find $(abspath ./csrc/common) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
# CSRCS += $(SRC_AUTO_BIND) 等到需要nvboard再加上

# rules for verilator
INCFLAGS = $(addprefix -I, $(INC_PATH)) -I$(abspath ./csrc/npc_soc) -I$(abspath ./csrc/common) -I$(abspath ./csrc/common/dev)
# SDL2 flags (via pkg-config; fallback to common defaults)
SDL2_CFLAGS := $(shell pkg-config --cflags sdl2 2>/dev/null)
SDL2_LDFLAGS := $(shell pkg-config --libs sdl2 2>/dev/null)
ifeq ($(strip $(SDL2_CFLAGS)),)
SDL2_CFLAGS := -I/usr/include/SDL2
SDL2_LDFLAGS := -lSDL2
endif


CXXFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\"" -std=c++11 -I$(AM_HOME)/am/include $(SDL2_CFLAGS)
# 添加-lrt用于时间函数 + pthread用于键盘线程 + SDL2
LDFLAGS += -ldl -lrt -lpthread $(SDL2_LDFLAGS)

$(BIN): $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE)
	@rm -rf $(OBJ_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) \
        -I$(abspath ./vsrc/npc_soc) \
        --top-module $(TOPNAME) $^ \
        $(addprefix -CFLAGS , $(CXXFLAGS)) $(addprefix -LDFLAGS , $(LDFLAGS)) \
        --Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

# 构建不生成VCD波形的版本（用于性能评估）
$(BIN)-notrace: $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE)
	@rm -rf $(OBJ_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS_NO_TRACE) \
        --top-module $(TOPNAME) $^ \
        $(addprefix -CFLAGS , $(CXXFLAGS) -DVM_TRACE=0) $(addprefix -LDFLAGS , $(LDFLAGS)) \
        --Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

# 波形文件路径
WAVE_FILE = $(BUILD_DIR)/dump.vcd

all: default

run: $(BIN)
	@if [ -n "$(IMG)" ]; then \
        echo "Running NPC with program: $(IMG)"; \
        $(BIN) $(IMG); \
	else \
        echo "Running NPC without program specified"; \
        $(BIN); \
	fi

# 运行不生成VCD的版本（用于性能评估）
run-notrace: $(BIN)-notrace
	@if [ -n "$(IMG)" ]; then \
        echo "Running NPC (no VCD) with program: $(IMG)"; \
        $(BIN) $(IMG); \
	else \
        echo "Running NPC (no VCD) without program specified"; \
        $(BIN); \
	fi

wave: $(BIN)
	@echo "Running simulation with wave tracing enabled..."
	@$(BIN)
	@echo "Opening waveform viewer..."
	@if [ -f $(WAVE_FILE) ]; then \
        $(GTKWAVE) $(WAVE_FILE); \
	else \
        echo "Warning: Expected wave file not found at $(WAVE_FILE)"; \
        echo "Searching for VCD files in $(BUILD_DIR)..."; \
        FOUND_VCD=$$(find $(BUILD_DIR) -name "*.vcd"); \
        if [ -n "$$FOUND_VCD" ]; then \
            echo "Found VCD file: $$FOUND_VCD"; \
            $(GTKWAVE) $$FOUND_VCD; \
        else \
            echo "Error: No VCD files found in $(BUILD_DIR)."; \
            echo "Check your testbench code to ensure it's generating waveform data."; \
            exit 1; \
        fi; \
	fi

# 添加 help 目标 - 显示可用命令
help:
	@echo "NPC Makefile 帮助 (npc_soc 独立仿真配置)"
	@echo "========================================="
	@echo "可用目标："
	@echo "  default, all   : 构建仿真可执行文件"
	@echo "  run            : 运行仿真"
	@echo "  run-notrace    : 运行仿真（不生成VCD）"
	@echo "  wave           : 运行仿真并打开 GTKWave"
	@echo "  clean          : 清除所有构建产物"
	@echo "  help           : 显示此帮助信息"

clean:
	rm -rf $(BUILD_DIR)

.PHONY: default all clean run wave help