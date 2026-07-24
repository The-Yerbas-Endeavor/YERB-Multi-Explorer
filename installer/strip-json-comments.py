#!/usr/bin/env python3
"""Convert the explorer's JSON-with-comments template into strict JSON.

The converter removes // and /* ... */ comments only when they occur outside
JSON strings, preserves URLs and comment-like text inside strings, and removes
trailing commas before object/array closing tokens.
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


def remove_trailing_commas(text: str) -> str:
    """Remove commas followed only by whitespace and then } or ], outside strings."""
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(text):
        char = text[index]

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

        if char == ",":
            lookahead = index + 1
            while lookahead < len(text) and text[lookahead].isspace():
                lookahead += 1
            if lookahead < len(text) and text[lookahead] in "}]":
                index += 1
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

    try:
        cleaned = strip_json_comments(source.read_text(encoding="utf-8"))
        cleaned = remove_trailing_commas(cleaned)
        parsed = json.loads(cleaned)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"Unable to convert settings template to strict JSON: {exc}", file=sys.stderr)
        return 1

    destination.write_text(
        json.dumps(parsed, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
