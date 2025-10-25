# NPC 架构规划与重构指南

## 当前状态
- ✅ 基本功能完整的单周期处理器
- ✅ 支持RISC-V基本指令集
- ✅ 通过am-tests验证
- ✅ 初步模块化（InstructionDecoder分离）

## 架构演进规划

### 阶段1：当前状态 - 单体设计
```
top.v
├── IFU逻辑 (内嵌在top.v中)
├── EXU.v (包含所有执行逻辑)
│   ├── 指令译码 (IDU功能)
│   ├── 算术逻辑 (ALU功能)
│   ├── 分支控制 (BRU功能)
│   ├── 访存控制 (LSU功能)
│   └── CSR管理 (CSR功能)
├── MEM.v (内存模块)
└── RegisterFile.v (寄存器文件)
```

### 阶段2：模块化分离 (为总线接口准备)
```
top.v
├── core/
│   ├── IFU.v (指令获取单元)
│   ├── IDU.v (指令译码单元)
│   ├── EXU.v (执行单元，简化)
│   ├── LSU.v (访存单元)
│   └── CSR.v (控制状态寄存器)
├── bus/
│   ├── AXI4_Lite_Master.v (AXI4-Lite主设备接口)
│   └── BusArbiter.v (总线仲裁器)
├── utils/
│   ├── InstructionDecoder.v
│   ├── ALU.v
│   ├── BranchUnit.v
│   ├── RegisterFile.v
│   └── PerformanceCounters.v
└── MEM.v
```

### 阶段3：总线接口集成 (B1阶段)
- 实现AXI4-Lite总线协议
- 支持valid/ready握手机制
- 为SoC集成做准备

### 阶段4：SoC集成 (B2阶段)
- 接入ysyxSoC环境
- 支持多种外设访问
- 地址空间管理

### 阶段5：性能优化 (B3阶段)
- 添加指令缓存 (ICache)
- 添加数据缓存 (DCache)
- 性能计数器和分析

### 阶段6：流水线实现 (B4阶段)
- 五级流水线设计
- 冲突检测和转发
- 分支预测

## 重构原则

### 1. 渐进式重构
- 每次只改变一个模块
- 每次重构后都要验证功能
- 保持向后兼容性

### 2. 接口标准化
- 使用valid/ready握手协议
- 统一的总线接口规范
- 参数化设计

### 3. 可测试性
- 保持DiffTest接口
- 添加性能监控接口
- 支持波形调试

## 验证方法

### 基本功能验证
```bash
cd /home/hy258/ysyx-workbench/am-kernels/tests/am-tests
make ARCH=riscv32e-npc run
```

### 性能测试
```bash
cd /home/hy258/ysyx-workbench/am-kernels/tests/cpu-tests
make ARCH=riscv32e-npc ALL=dummy run
```

## 目录结构说明

### 当前文件组织
- `top.v` - 顶层模块
- `EXU.v` - 执行单元（包含所有执行逻辑）
- `InstructionDecoder.v` - 指令解码器
- `MEM.v` - 内存模块
- `RegisterFile.v` - 寄存器文件
- `flip.v` - 触发器模板
- `mux.v` - 选择器模板

### 预留目录结构
- `core/` - 处理器核心模块
- `bus/` - 总线接口模块
- `utils/` - 通用工具模块
- `cache/` - 缓存相关模块

## 下一步计划

1. **保持当前功能稳定**：确保所有测试通过
2. **逐步模块分离**：按需要分离EXU中的子功能
3. **添加总线接口**：为SoC集成做准备
4. **性能监控**：添加计数器和分析工具
5. **流水线准备**：设计流水线寄存器和控制逻辑

## 注意事项

- 每次重构都要通过验证测试
- 保持代码的可读性和可维护性
- 为后续扩展预留接口
- 遵循RISC-V规范和ysyx项目要求