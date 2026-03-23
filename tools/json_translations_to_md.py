#!/usr/bin/env python3
"""
将翻译 JSON 转为 Markdown（按 id 排序，id 与条目一一对应）。

支持的输入形状：
  - [{"id": 0, "jp": "...", "zh": "..."}, ...]
  - {"translations": [ ... ]}，数组元素可为 {id, jp, zh} 或 {id, value}
  - 顶层即为 "translations" 数组时，也可传入 {"translations": [...]}

用法：
  python3 json_translations_to_md.py < in.json > out.md
  python3 json_translations_to_md.py -i in.json -o out.md
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def _normalize_items(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, dict) and "translations" in raw:
        raw = raw["translations"]
    if not isinstance(raw, list):
        raise ValueError("顶层应为数组，或包含 translations 数组的对象")
    return raw


def _sort_key(item: dict[str, Any]) -> tuple[int, int]:
    i = item.get("id")
    if isinstance(i, int):
        return (0, i)
    if isinstance(i, str) and i.isdigit():
        return (0, int(i))
    return (1, 0)


def translations_to_markdown(data: Any, title: str = "Translations") -> str:
    items = _normalize_items(data)
    items = sorted(items, key=_sort_key)
    lines: list[str] = [f"## {title}", ""]
    for item in items:
        if not isinstance(item, dict):
            continue
        tid = item.get("id", "")
        lines.append(f"### {tid}")
        lines.append("")
        if "jp" in item or "zh" in item:
            if "jp" in item:
                lines.append("**日本語**")
                lines.append("")
                lines.append(str(item["jp"]))
                lines.append("")
            if "zh" in item:
                lines.append("**中文**")
                lines.append("")
                lines.append(str(item["zh"]))
                lines.append("")
        elif "value" in item:
            lines.append(str(item["value"]))
            lines.append("")
        else:
            lines.append("```json")
            lines.append(json.dumps(item, ensure_ascii=False, indent=2))
            lines.append("```")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description="翻译 JSON → Markdown")
    p.add_argument(
        "-i",
        "--input",
        help="输入 JSON 文件（缺省为 stdin）",
    )
    p.add_argument(
        "-o",
        "--output",
        help="输出 Markdown 文件（缺省为 stdout）",
    )
    p.add_argument(
        "-t",
        "--title",
        default="Translations",
        help="Markdown 二级标题文本",
    )
    args = p.parse_args()

    if args.input:
        with open(args.input, encoding="utf-8") as f:
            raw = json.load(f)
    else:
        raw = json.load(sys.stdin)

    md = translations_to_markdown(raw, title=args.title)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(md)
    else:
        sys.stdout.write(md)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
