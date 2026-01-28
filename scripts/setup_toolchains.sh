#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN_DIR="${ROOT_DIR}/.toolchains"
MILL_DIR="${TOOLCHAIN_DIR}/mill"

mkdir -p "${MILL_DIR}"

required_packages=()
if ! command -v curl >/dev/null 2>&1; then
  required_packages+=(curl)
fi
if ! command -v python3 >/dev/null 2>&1; then
  required_packages+=(python3)
fi
if ! command -v riscv64-linux-gnu-gcc >/dev/null 2>&1; then
  required_packages+=(gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu)
fi
if ! command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
  required_packages+=(gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf)
fi

if ((${#required_packages[@]})); then
  sudo apt-get update
  sudo apt-get install -y "${required_packages[@]}"
fi

MILL_BIN="${MILL_DIR}/mill"
if [[ ! -x "${MILL_BIN}" ]]; then
  echo "Downloading mill..."
  MILL_VERSION="$(curl -s https://api.github.com/repos/com-lihaoyi/mill/releases?per_page=100 \
    | python3 -c 'import json,sys;releases=json.load(sys.stdin);print(next((r.get("tag_name","") for r in releases if r.get("tag_name") and any(a.get("name")==r.get("tag_name") for a in r.get("assets",[]))), ""))')"
  MILL_VERSION="${MILL_VERSION#v}"
  if [[ -z "${MILL_VERSION}" ]]; then
    echo "Failed to find a mill release asset." >&2
    exit 1
  fi
  MILL_URL="https://github.com/com-lihaoyi/mill/releases/download/${MILL_VERSION}/${MILL_VERSION}"

  curl -L --fail -o "${MILL_BIN}.tmp" "${MILL_URL}"
  mv "${MILL_BIN}.tmp" "${MILL_BIN}"
  chmod +x "${MILL_BIN}"
fi

echo "riscv64-linux-gnu-gcc: $(command -v riscv64-linux-gnu-gcc)"
echo "riscv64-unknown-elf-gcc: $(command -v riscv64-unknown-elf-gcc)"
echo "mill: ${MILL_BIN}"
echo "Add mill to PATH: export PATH=\"${MILL_DIR}:\$PATH\""
