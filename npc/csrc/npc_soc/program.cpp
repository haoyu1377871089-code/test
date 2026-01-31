#include "sim.h"
#include "Vtop.h"
#include "verilated_vcd_c.h"
#include <fstream>
#include <iostream>
#include <iomanip>
#include <vector>
#include <cstdint>

extern "C" void pmem_load_binary(const char* filename, uint32_t start_addr);

std::map<uint32_t, uint32_t> pc_inst;

std::vector<uint8_t> readBinaryFile(const std::string &filename) {
    std::ifstream file(filename, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        std::cerr << "无法打开文件: " << filename << std::endl;
        exit(1);
    }

    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> buffer(size);
    if (!file.read(reinterpret_cast<char *>(buffer.data()), size)) {
        std::cerr << "读取文件失败: " << filename << std::endl;
        exit(1);
    }

    return buffer;
}

void buildInstructionMap(const std::vector<uint8_t> &program) {
    // 根据小端32位指令将镜像构建为 PC->inst 映射
    for (size_t i = 0; i + 3 < program.size(); i += 4) {
        uint32_t inst = 0;
        inst |= static_cast<uint32_t>(program[i]);
        inst |= static_cast<uint32_t>(program[i + 1]) << 8;
        inst |= static_cast<uint32_t>(program[i + 2]) << 16;
        inst |= static_cast<uint32_t>(program[i + 3]) << 24;
        pc_inst[0x80000000 + static_cast<uint32_t>(i)] = inst;
    }
}

void loadImageToMemory(const std::string &filename, uint32_t start_addr) {
    pmem_load_binary(filename.c_str(), start_addr);
}