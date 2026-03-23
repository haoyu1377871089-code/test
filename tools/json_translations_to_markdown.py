#!/usr/bin/env python3
"""
将翻译 JSON 转为 Markdown。支持：
  - 顶层数组，或 {"translations": [...]}
  - 每条含 id；正文为 value，或 jp + zh（或其它字符串字段）
按 id 数值排序输出，保证顺序稳定。
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def _load_items(raw: str) -> list[dict[str, Any]]:
    data = json.loads(raw)
    if isinstance(data, dict) and "translations" in data:
        items = data["translations"]
    elif isinstance(data, list):
        items = data
    else:
        raise ValueError("JSON 须为数组，或含 translations 键的对象")
    if not isinstance(items, list):
        raise ValueError("translations 须为数组")
    out: list[dict[str, Any]] = []
    for i, row in enumerate(items):
        if not isinstance(row, dict):
            raise ValueError(f"第 {i} 条不是对象")
        if "id" not in row:
            raise ValueError(f"第 {i} 条缺少 id")
        out.append(row)
    return out


def _sort_key(row: dict[str, Any]) -> tuple[int, int]:
    try:
        return (int(row["id"]), 0)
    except (TypeError, ValueError):
        return (0, hash(str(row["id"])) & 0x7FFFFFFF)


def _escape_cell(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", "<br>")


def _format_entry(row: dict[str, Any]) -> str:
    rid = row["id"]
    lines: list[str] = [f"### `{rid}`", ""]

    if "value" in row and row["value"] is not None:
        v = row["value"]
        if not isinstance(v, str):
            v = json.dumps(v, ensure_ascii=False)
        lines.append(v.strip())
        lines.append("")
        return "\n".join(lines)

    # 多语言字段：除 id 外所有字符串键，按键名排序以稳定输出
    skip = {"id"}
    pairs = [
        (k, row[k])
        for k in sorted(row.keys())
        if k not in skip and isinstance(row[k], str)
    ]
    if not pairs:
        lines.append(json.dumps(row, ensure_ascii=False, indent=2))
        lines.append("")
        return "\n".join(lines)

    for k, v in pairs:
        lines.append(f"**{k}:** {v}")
    lines.append("")
    return "\n".join(lines)


def json_to_markdown(raw: str, *, as_table: bool = False) -> str:
    items = sorted(_load_items(raw), key=_sort_key)
    if not items:
        return ""

    if as_table:
        # 表头：id + 所有出现过的非 id 字符串列
        cols: list[str] = ["id"]
        for row in items:
            for k in row:
                if k == "id":
                    continue
                if isinstance(row[k], str) and k not in cols:
                    cols.append(k)
        cols = ["id"] + sorted(c for c in cols if c != "id")
        header = "| " + " | ".join(cols) + " |"
        sep = "| " + " | ".join("---" for _ in cols) + " |"
        body_lines = [header, sep]
        for row in items:
            cells = []
            for c in cols:
                if c == "id":
                    cells.append(str(row.get("id", "")))
                else:
                    v = row.get(c, "")
                    if not isinstance(v, str):
                        v = "" if v is None else json.dumps(v, ensure_ascii=False)
                    cells.append(_escape_cell(v))
            body_lines.append("| " + " | ".join(cells) + " |")
        return "\n".join(body_lines) + "\n"

    parts = ["# 翻译条目\n"]
    for row in items:
        parts.append(_format_entry(row))
    return "\n".join(parts).rstrip() + "\n"


def main() -> None:
    p = argparse.ArgumentParser(description="翻译 JSON → Markdown（按 id 排序）")
    p.add_argument(
        "input",
        nargs="?",
        help="输入 JSON 文件；省略则从 stdin 读",
    )
    p.add_argument(
        "-o",
        "--output",
        help="输出 Markdown 文件；省略则打印到 stdout",
    )
    p.add_argument(
        "--table",
        action="store_true",
        help="输出为 Markdown 表格（适合同构字段）",
    )
    args = p.parse_args()

    if args.input:
        with open(args.input, encoding="utf-8") as f:
            raw = f.read()
    else:
        raw = sys.stdin.read()

    try:
        md = json_to_markdown(raw, as_table=args.table)
    except (json.JSONDecodeError, ValueError) as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(md)
    else:
        sys.stdout.write(md)


if __name__ == "__main__":
    main()
