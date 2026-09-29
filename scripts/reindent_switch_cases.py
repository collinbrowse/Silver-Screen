#!/usr/bin/env python3
"""Indent switch case labels and bodies per .cursor/rules/formatting.mdc.

Only reindents inside `switch` statements. Enum `case` declarations are unchanged.

Run from repo root: python3 scripts/reindent_switch_cases.py [--check] [paths...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SWITCH_RE = re.compile(r"\bswitch\b")
CASE_RE = re.compile(r"^(case\b|default\b)")
CLOSE_BRACE_RE = re.compile(r"^\}")

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATHS = [ROOT / "TheSilverScreen", ROOT / "TheSilverScreenTests"]


def strip_strings_and_comments(line: str) -> str:
    out: list[str] = []
    i = 0
    in_string = False
    escape = False
    in_line_comment = False
    while i < len(line):
        ch = line[i]
        if in_line_comment:
            break
        if in_string:
            out.append(" ")
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            in_line_comment = True
            out.append("  ")
            i += 2
            continue
        if ch == '"':
            in_string = True
            out.append(" ")
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def leading_spaces(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def brace_delta(line: str) -> int:
    cleaned = strip_strings_and_comments(line)
    return cleaned.count("{") - cleaned.count("}")


def reindent_switch_block(lines: list[str], start: int, switch_indent: int) -> tuple[list[str], int]:
    unit = 4
    case_indent = switch_indent + unit
    body_indent = case_indent + unit

    out: list[str] = []
    i = start
    out.append(lines[i])
    depth = brace_delta(lines[i])
    i += 1

    while i < len(lines) and depth > 0:
        raw = lines[i]
        stripped = raw.lstrip()
        spaces = leading_spaces(raw)

        if depth == 1 and CLOSE_BRACE_RE.match(stripped) and spaces == switch_indent:
            out.append(raw)
            depth += brace_delta(raw)
            i += 1
            break

        if depth == 1 and CASE_RE.match(stripped):
            out.append(" " * case_indent + stripped)
            i += 1
            depth += brace_delta(out[-1])
            while i < len(lines):
                if depth == 1:
                    nxt = lines[i]
                    nxt_stripped = nxt.lstrip()
                    nxt_spaces = leading_spaces(nxt)
                    if CASE_RE.match(nxt_stripped) and nxt_spaces <= case_indent:
                        break
                    if CLOSE_BRACE_RE.match(nxt_stripped) and nxt_spaces == switch_indent:
                        break
                    if nxt_stripped:
                        if nxt_spaces < body_indent:
                            out.append(" " * body_indent + nxt_stripped)
                        else:
                            out.append(nxt)
                    else:
                        out.append(nxt)
                    depth += brace_delta(nxt)
                    i += 1
                    continue
                inner = lines[i]
                inner_stripped = inner.lstrip()
                inner_spaces = leading_spaces(inner)
                if depth == 2 and CASE_RE.match(inner_stripped) and inner_spaces <= case_indent:
                    break
                if depth == 2 and CLOSE_BRACE_RE.match(inner_stripped) and inner_spaces == switch_indent:
                    break
                if depth == 2 and inner_stripped and inner_spaces < body_indent:
                    out.append(" " * body_indent + inner_stripped)
                else:
                    out.append(inner)
                depth += brace_delta(inner)
                i += 1
            continue

        out.append(raw)
        depth += brace_delta(raw)
        i += 1

    return out, i


def reindent_source(text: str) -> str:
    lines = text.splitlines(keepends=True)
    if not lines:
        return text
    if not lines[-1].endswith(("\n", "\r")):
        lines[-1] += "\n"

    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.lstrip()
        if SWITCH_RE.search(stripped) and "{" in strip_strings_and_comments(stripped):
            switch_indent = leading_spaces(line)
            segment, next_i = reindent_switch_block(lines, i, switch_indent)
            out.extend(segment)
            i = next_i
            continue
        out.append(line)
        i += 1

    return "".join(out)


def iter_swift_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        path = path if path.is_absolute() else ROOT / path
        if path.is_file() and path.suffix == ".swift":
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("*.swift")))
    return files


def main() -> int:
    check = False
    paths: list[Path] = []
    for arg in sys.argv[1:]:
        if arg == "--check":
            check = True
        else:
            paths.append(Path(arg))
    if not paths:
        paths = DEFAULT_PATHS

    problems: list[str] = []
    for path in iter_swift_files(paths):
        original = path.read_text(encoding="utf-8")
        updated = reindent_source(original)
        if original == updated:
            continue
        rel = path.relative_to(ROOT)
        if check:
            problems.append(str(rel))
        else:
            path.write_text(updated, encoding="utf-8")
            print(f"  ok  {rel}")

    if check:
        if problems:
            print(f"{len(problems)} file(s) need switch reindent:")
            for problem in problems:
                print(f"  - {problem}")
            return 1
        print("  ok  all switch blocks indented")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
