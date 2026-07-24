#!/usr/bin/env python3
"""Convert the explorer's JSON-with-comments template into strict JSON."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def strip_comments(source: str) -> str:
    """Remove // and /* */ comments while preserving quoted strings."""
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(source):
        char = source[index]
        nxt = source[index + 1] if index + 1 < len(source) else ""

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

        if char == "/" and nxt == "/":
            index += 2
            while index < len(source) and source[index] not in "\r\n":
                index += 1
            continue

        if char == "/" and nxt == "*":
            index += 2
            while index + 1 < len(source) and not (
                source[index] == "*" and source[index + 1] == "/"
            ):
                if source[index] in "\r\n":
                    output.append(source[index])
                index += 1
            if index + 1 >= len(source):
                raise ValueError("Unterminated block comment")
            index += 2
            continue

        output.append(char)
        index += 1

    return "".join(output)


def strip_trailing_commas(source: str) -> str:
    """Remove commas immediately before } or ] outside quoted strings."""
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(source):
        char = source[index]

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
            while lookahead < len(source) and source[lookahead].isspace():
                lookahead += 1
            if lookahead < len(source) and source[lookahead] in "}]":
                index += 1
                continue

        output.append(char)
        index += 1

    return "".join(output)


def remove_xeggex(value):
    """Remove Xeggex keys and replace Xeggex string values with Nestex."""
    if isinstance(value, dict):
        cleaned = {}
        for key, item in value.items():
            if str(key).lower() == "xeggex":
                continue
            cleaned[key] = remove_xeggex(item)
        return cleaned
    if isinstance(value, list):
        return [remove_xeggex(item) for item in value]
    if isinstance(value, str) and value.lower() == "xeggex":
        return "nestex"
    return value


def force_nestex_default(settings: dict) -> None:
    markets = settings.get("markets_page")
    if isinstance(markets, dict):
        default_exchange = markets.setdefault("default_exchange", {})
        if isinstance(default_exchange, dict):
            default_exchange["exchange_name"] = "nestex"
            default_exchange["trading_pair"] = "YERB/USDT"


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} INPUT OUTPUT", file=sys.stderr)
        return 2

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    try:
        raw = input_path.read_text(encoding="utf-8")
        normalized = strip_trailing_commas(strip_comments(raw))
        parsed = remove_xeggex(json.loads(normalized))
        if isinstance(parsed, dict):
            force_nestex_default(parsed)
        output_path.write_text(
            json.dumps(parsed, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"Unable to convert {input_path}: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
