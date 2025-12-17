# SystemC TLM 系统级建模示例

本目录包含多个SystemC TLM（Transaction-Level Modeling）示例，用于系统级建模和虚拟原型设计。

## 方案列表

### 1. 基础TLM-2.0通信示例 (basic_tlm2/)
- **用途**: 演示TLM-2.0基本的阻塞传输接口
- **内容**: Initiator和Target之间的简单内存读写事务
- **适用场景**: 学习TLM基础概念，简单的总线通信建模

### 2. AXI总线系统 (axi_system/)
- **用途**: 基于TLM-2.0实现AXI总线协议建模
- **内容**: AXI Master、AXI Slave、互连器和内存模型
- **适用场景**: SoC总线架构建模，多主多从系统

### 3. CPU-Cache-Memory层次 (cpu_cache_mem/)
- **用途**: 建模完整的存储层次结构
- **内容**: 简化CPU模型、L1/L2 Cache、主存储器
- **适用场景**: 存储系统性能分析，缓存一致性研究

### 4. DMA控制器系统 (dma_system/)
- **用途**: DMA数据传输建模
- **内容**: DMA控制器、外设、内存和中断机制
- **适用场景**: 高速数据传输系统，I/O性能优化

### 5. 多核处理器原型 (multicore/)
- **用途**: 多核处理器虚拟原型
- **内容**: 多个CPU核心、共享缓存、互连网络
- **适用场景**: 并行系统研究，多核软件开发

## 编译和运行

每个示例都包含Makefile，使用方法：
```bash
cd <example_dir>
make
./sim
```

## 依赖

- SystemC 2.3.3 或更高版本
- C++11 或更高版本编译器
- (可选) TLM-2.0 库（通常包含在SystemC中）

## 学习路径

1. 从 `basic_tlm2` 开始了解TLM基础
2. 学习 `axi_system` 了解总线建模
3. 探索 `cpu_cache_mem` 理解存储层次
4. 研究 `dma_system` 和 `multicore` 进行高级建模
