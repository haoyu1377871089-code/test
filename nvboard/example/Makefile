TOPNAME = top
# 指定了约束文件的路径
NXDC_FILES = constr/top.nxdc
# ❓表示如果没有被定义过则赋为空。INC_PATH作用是定义一个可选的头文件搜索变量
INC_PATH ?=

VERILATOR = verilator
VERILATOR_CFLAGS += -MMD --build -cc  \
				-O3 --x-assign fast --x-initial fast --noassert
# -MMD
# 让 GCC/Clang 生成依赖文件（.d），用于自动管理头文件依赖
# --build
# 在生成 C++ 仿真模型后，自动编译并链接出可执行仿真程序
# -cc
# 告诉 Verilator 产出 C++ 仿真代码
# -O3
# 对生成的 C++ 代码做最高级别的优化
# --x-assign fast
# 对 assign 语句中 X（未知）状态做“快速”处理（可略过精确 4 值仿真）
# --x-initial fast
# 对 initial 语句中 X 状态同样做“快速”处理
# --noassert
# 在仿真时禁用 $assert、$fatal 等断言检查，略过相关开销
BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

default: $(BIN)

$(shell mkdir -p $(BUILD_DIR))

# constraint file
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
# 把 build/auto_bind.cpp 的绝对路径保存在 SRC_AUTO_BIND 中
$(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@
# 表示 “当约束文件（$(NXDC_FILES)）更新时，用 auto_pin_bind.py 脚本把它转换成 C++ 代码，输出到 auto_bind.cpp”。
# $^ 是所有依赖（这里就是 .nxdc 文件）
# $@ 是目标文件（这里是生成的 auto_bind.cpp）
# 生成的 auto_bind.cpp 中会有一段自动把顶层 Verilog 端口和板卡引脚绑定的代码，供 Verilator+NVBoard 仿真使用。
# project source
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
CSRCS += $(SRC_AUTO_BIND)

# rules for NVBoard
include $(NVBOARD_HOME)/scripts/nvboard.mk

# rules for verilator
INCFLAGS = $(addprefix -I, $(INC_PATH))
CXXFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\""
# -DTOP_NAME="Vtop"  

$(BIN): $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE)
	@rm -rf $(OBJ_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) \
		--top-module $(TOPNAME) $^ \
		$(addprefix -CFLAGS , $(CXXFLAGS)) $(addprefix -LDFLAGS , $(LDFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))
# $(VSRCS)：所有查到的 .v 文件（顶层及子模块）
# $(CSRCS)：所有 C/C++ 源 + 自动生成的 auto_bind.cpp
# $(NVBOARD_ARCHIVE)：NVBoard 自带的仿真库（在 nvboard.mk 里定义）
# 命令

# @rm -rf $(OBJ_DIR)：先删掉上次生成的中间目录 build/obj_dir
# 调用 Verilator：
# $(VERILATOR) $(VERILATOR_CFLAGS)：基本的仿真开关（见前面）
# --top-module $(TOPNAME)：指定顶层模块名 top
# $^：所有依赖文件（上面列的 .v/.cpp/.a）
# $(addprefix -CFLAGS ,$(CXXFLAGS))：把之前准备的头文件搜索路径、宏定义等传给内部 C++ 编译器
# $(addprefix -LDFLAGS ,$(LDFLAGS))：如果有额外链接选项，也一并传入
# --Mdir $(OBJ_DIR)：告诉 Verilator 把所有中间输出放到 build/obj_dir
# --exe -o $(abspath $(BIN))：生成可执行仿真程序并命名为 build/top

all: default

run: $(BIN)
	@$^

clean:
	rm -rf $(BUILD_DIR)

.PHONY: default all clean run
