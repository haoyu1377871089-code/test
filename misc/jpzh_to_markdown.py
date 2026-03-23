#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""将 [{id, jp, zh}, ...] 格式的 JSON 数组转为 Markdown（保留 id，便于对照）。"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


def array_to_markdown(data: List[Dict[str, Any]], title: Optional[str]) -> str:
    lines: list[str] = []
    if title:
        lines.append(f"# {title}")
        lines.append("")
    for item in data:
        i = item["id"]
        jp = str(item.get("jp", ""))
        zh = str(item.get("zh", ""))
        lines.append(f"## {i}")
        lines.append("")
        lines.append("**jp:**")
        lines.append("")
        lines.append(jp)
        lines.append("")
        lines.append("**zh:**")
        lines.append("")
        lines.append(zh)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description="JP/ZH 翻译 JSON 数组 → Markdown")
    p.add_argument("input_json", type=Path, help="含 [{id,jp,zh}] 的 JSON 文件路径")
    p.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="输出 .md 路径（默认与输入同名 .md）",
    )
    p.add_argument("-t", "--title", default=None, help="Markdown 一级标题（可选）")
    args = p.parse_args()

    raw = args.input_json.read_text(encoding="utf-8")
    data = json.loads(raw)
    if not isinstance(data, list):
        print("error: 根节点须为 JSON 数组", file=sys.stderr)
        return 1
    out = args.output or args.input_json.with_suffix(".md")
    out.write_text(array_to_markdown(data, args.title), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
