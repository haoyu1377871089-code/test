#!/usr/bin/env bash
# update_compile_commands.sh
# 一键捕获并汇总 AM、KLIB、AM-TESTS、NPC、NEMU 的编译命令到 compile_commands.json。
# 用法示例：
#   RESET=1 VERBOSE=1 ARCH=riscv32e-npc MAINARGS=h ./update_compile_commands.sh
#
# 可用环境变量：
#   ARCH      默认 "riscv32e-npc"（用于 AM 与 am-tests）
#   MAINARGS  默认 "h"（am-tests 运行参数）
#   RESET     设置为 1 时先删除旧 compile_commands.json
#   VERBOSE   设置为 1 时输出示例命中条目

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEAR_OUTPUT="${ROOT_DIR}/compile_commands.json"
ARCH_DEFAULT="riscv32e-npc"

ARCH="${ARCH:-${ARCH_DEFAULT}}"
MAINARGS="${MAINARGS:-h}"
RESET="${RESET:-0}"
VERBOSE="${VERBOSE:-0}"

msg()  { echo "[update] $*"; }
die()  { echo "[update] ERROR: $*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

if ! has bear; then
  die "bear 未找到。请先安装：sudo apt-get install bear"
fi

# 禁用 ccache，保证真实编译动作被记录
export CCACHE_DISABLE=1

# 可选重置输出文件
if [[ "${RESET}" == "1" ]]; then
  msg "重置 ${BEAR_OUTPUT}"
  rm -f "${BEAR_OUTPUT}"
fi

# Bear 执行助手：首个调用使用 --output 创建文件，其后使用 --append 追加
bear_run() {
  local cmd=("$@")
  if [[ ! -f "${BEAR_OUTPUT}" ]]; then
    msg "创建 ${BEAR_OUTPUT}：${cmd[*]}"
    bear --output "${BEAR_OUTPUT}" -- "${cmd[@]}"
  else
    msg "追加到 ${BEAR_OUTPUT}：${cmd[*]}"
    bear --append --output "${BEAR_OUTPUT}" -- "${cmd[@]}"
  fi
}

# AM: 构建 archive 以触发编译并捕获
build_am() {
  local am_dir="${ROOT_DIR}/abstract-machine/am"
  [[ -d "${am_dir}" ]] || return 0
  msg "重建 AM archive (ARCH=${ARCH})"
  bear_run make -C "${am_dir}" clean ARCH="${ARCH}"
  bear_run make -C "${am_dir}" -B ARCH="${ARCH}" archive
}

# KLIB: 构建 archive
build_klib() {
  local klib_dir="${ROOT_DIR}/abstract-machine/klib"
  [[ -d "${klib_dir}" ]] || return 0
  msg "重建 KLIB archive (ARCH=${ARCH})"
  bear_run make -C "${klib_dir}" clean ARCH="${ARCH}"
  bear_run make -C "${klib_dir}" -B ARCH="${ARCH}" archive
}

# AM-TESTS: 强制重建并运行
build_amtests() {
  local tests_dir="${ROOT_DIR}/am-kernels/tests/am-tests"
  [[ -d "${tests_dir}" ]] || return 0
  msg "重建 am-tests 并运行 (ARCH=${ARCH}, mainargs=${MAINARGS})"
  bear_run make -C "${tests_dir}" -B run ARCH="${ARCH}" mainargs="${MAINARGS}"
}

# NPC: 强制重建（包含 nvboard 与 verilator 生成）
build_npc() {
  local npc_dir="${ROOT_DIR}/npc"
  [[ -d "${npc_dir}" ]] || return 0
  msg "重建 NPC"
  bear_run make -C "${npc_dir}" clean
  bear_run make -C "${npc_dir}" -B
}

# NPC obj_dir: 通过内部 Vtop.mk 捕获 csrc 的编译命令
build_npc_obj() {
  local obj_dir="${ROOT_DIR}/npc/build/obj_dir"
  local mk="${obj_dir}/Vtop.mk"
  if [[ -f "${mk}" ]]; then
    msg "在 obj_dir 捕获 NPC csrc 编译"
    bear_run make -C "${obj_dir}" -f "Vtop.mk" -B top
  else
    msg "跳过 obj_dir 捕获；未找到 ${mk}（请先执行 NPC 构建）"
  fi
}

# NEMU: 强制重建
build_nemu() {
  local nemu_dir="${ROOT_DIR}/nemu"
  [[ -d "${nemu_dir}" ]] || return 0
  msg "重建 NEMU"
  bear_run make -C "${nemu_dir}" clean
  bear_run make -C "${nemu_dir}" -B
}

# 执行所有步骤
build_am
build_klib
build_amtests
build_npc
build_npc_obj
build_nemu

# 统计结果并输出提示
if [[ -f "${BEAR_OUTPUT}" ]]; then
  count=$(grep -c '"file": ' "${BEAR_OUTPUT}" || true)
  msg "完成。compile_commands.json 条目数：${count}"
  if [[ "${VERBOSE}" == "1" ]]; then
    msg "示例命中条目："
    grep -n "/am-kernels/tests/am-tests/src/main.c" "${BEAR_OUTPUT}" || true
    grep -n "/abstract-machine/am/src/riscv/npc/trm.c" "${BEAR_OUTPUT}" || true
    grep -n "/abstract-machine/klib/src/string.c" "${BEAR_OUTPUT}" || true
    grep -n "/npc/csrc/main.cpp" "${BEAR_OUTPUT}" || true
    grep -n "/nemu/src/nemu-main.c" "${BEAR_OUTPUT}" || true
  fi
else
  die "失败：未生成 ${BEAR_OUTPUT}"
fi