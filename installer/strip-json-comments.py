#!/usr/bin/env python3
"""Convert the explorer's commented JSON template into strict JSON.

The parser removes // and /* ... */ comments only when they occur outside JSON
strings, preserving URLs and comment-like text contained in string values.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def strip_json_comments(text: str) -> str:
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue

        if char == "/" and next_char == "/":
            index += 2
            while index < len(text) and text[index] not in "\r\n":
                index += 1
            continue

        if char == "/" and next_char == "*":
            index += 2
            while index + 1 < len(text) and text[index:index + 2] != "*/":
                if text[index] in "\r\n":
                    output.append(text[index])
                index += 1
            if index + 1 >= len(text):
                raise ValueError("Unterminated block comment in settings template")
            index += 2
            continue

        output.append(char)
        index += 1

    return "".join(output)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} INPUT OUTPUT", file=sys.stderr)
        return 2

    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    cleaned = strip_json_comments(source.read_text(encoding="utf-8"))

    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        print(f"Invalid JSON after removing comments: {exc}", file=sys.stderr)
        return 1

    destination.write_text(
        json.dumps(parsed, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
