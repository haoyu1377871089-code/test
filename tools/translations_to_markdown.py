#!/usr/bin/env python3
"""
Convert translation JSON to Markdown.

Supports:
  - Top-level array: [{"id": 0, "jp": "...", "zh": "..."}, ...]
  - Wrapped object: {"translations": [{"id": 0, "value": "..."}, ...]}

When only "value" is present, it is emitted as the body under each id heading.
When "jp" / "zh" (or any extra string fields) are present, they are labeled lines.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def _load_payload(raw: str) -> list[dict[str, Any]]:
    data = json.loads(raw)
    if isinstance(data, dict) and "translations" in data:
        inner = data["translations"]
        if not isinstance(inner, list):
            raise ValueError('"translations" must be an array')
        return inner
    if isinstance(data, list):
        return data
    raise ValueError("JSON must be an array or an object with a translations array")


def _sort_key(row: dict[str, Any]) -> tuple[int, int]:
    rid = row.get("id")
    if isinstance(rid, int):
        return (0, rid)
    if isinstance(rid, str) and rid.isdigit():
        return (0, int(rid))
    return (1, 0)


def row_to_markdown(row: dict[str, Any]) -> str:
    rid = row.get("id", "")
    lines: list[str] = [f"## {rid}", ""]

    reserved = {"id"}
    has_labeled = any(k in row for k in ("jp", "zh", "en"))
    val_only = "value" in row and isinstance(row.get("value"), str) and not has_labeled

    if val_only:
        lines.append(row["value"])
        lines.append("")
    else:
        # Prefer labeled fields in a stable order
        for key in ("jp", "zh", "en", "value"):
            if key in row and key not in reserved:
                v = row[key]
                if isinstance(v, str) and v != "":
                    label = key.upper() if key in ("jp", "zh", "en") else key
                    lines.append(f"**{label}:** {v}")
                    lines.append("")

    for key in sorted(row.keys()):
        if key in reserved or key in ("jp", "zh", "en", "value"):
            continue
        val = row[key]
        if isinstance(val, str) and val != "":
            lines.append(f"**{key}:** {val}")
            lines.append("")

    # Trim trailing blank lines, keep single blank between sections
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n\n"


def convert(raw_json: str) -> str:
    rows = _load_payload(raw_json)
    rows = sorted(rows, key=_sort_key)
    parts = ["# Translations\n\n"]
    for row in rows:
        if not isinstance(row, dict):
            continue
        parts.append(row_to_markdown(row))
    return "".join(parts).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert translation JSON to Markdown.")
    parser.add_argument(
        "input",
        nargs="?",
        type=Path,
        help="Input JSON file (default: stdin)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output Markdown file (default: stdout)",
    )
    args = parser.parse_args()

    if args.input:
        raw = args.input.read_text(encoding="utf-8")
    else:
        raw = sys.stdin.read()

    md = convert(raw)

    if args.output:
        args.output.write_text(md, encoding="utf-8")
    else:
        sys.stdout.write(md)


if __name__ == "__main__":
    main()
