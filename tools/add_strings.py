#!/usr/bin/env python3
"""Append interface strings to both catalogs.

Usage: python3 tools/add_strings.py '{"English key": "中文", ...}'
Keys already present are skipped. English values always equal the key.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def quote(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main() -> None:
    entries = json.loads(sys.argv[1])
    for lang in ("en", "zh-Hans"):
        path = ROOT / "Resources" / f"{lang}.lproj" / "Localizable.strings"
        text = path.read_text()
        lines = [
            f'"{quote(key)}" = "{quote(key if lang == "en" else zh)}";'
            for key, zh in entries.items()
            if f'"{quote(key)}" =' not in text
        ]
        if lines:
            path.write_text(text.rstrip("\n") + "\n" + "\n".join(lines) + "\n")
        print(f"{lang}: added {len(lines)}")


if __name__ == "__main__":
    main()
