#!/usr/bin/env python3
"""Indent multiline call/initializer arguments per .cursor/rules/formatting.mdc.

Run from repo root: python3 scripts/reindent_multiline_arguments.py [--check] [paths...]
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATHS = [ROOT / "TheSilverScreen", ROOT / "TheSilverScreenTests"]
INDENT = 4


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


def paren_delta(line: str) -> int:
    cleaned = strip_strings_and_comments(line)
    return cleaned.count("(") - cleaned.count(")")


def opens_multiline_call(line: str) -> bool:
    cleaned = strip_strings_and_comments(line)
    if "(" not in cleaned:
        return False
    return paren_delta(line) > 0


@dataclass
class CallFrame:
    open_depth: int
    base_indent: int
    arg_indent: int


def reindent_source(text: str) -> str:
    lines = text.splitlines(keepends=True)
    if not lines:
        return text
    if not lines[-1].endswith(("\n", "\r")):
        lines[-1] += "\n"

    depth = 0
    stack: list[CallFrame] = []
    out: list[str] = []

    for line in lines:
        stripped = line.lstrip()
        indent = leading_spaces(line)
        depth_before = depth

        if stack and stripped:
            frame = stack[-1]
            if depth_before >= frame.open_depth:
                is_closing = stripped.startswith(")") and indent == frame.base_indent
                if not is_closing and indent <= frame.base_indent:
                    line = " " * frame.arg_indent + stripped
                    indent = frame.arg_indent
                elif not is_closing and indent < frame.arg_indent:
                    line = " " * frame.arg_indent + stripped
                    indent = frame.arg_indent

        out.append(line)
        depth += paren_delta(line)

        if opens_multiline_call(line):
            stack.append(
                CallFrame(
                    open_depth=depth,
                    base_indent=leading_spaces(line),
                    arg_indent=leading_spaces(line) + INDENT,
                )
            )

        while stack and depth < stack[-1].open_depth:
            stack.pop()

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
            print(f"{len(problems)} file(s) need multiline argument reindent:")
            for problem in problems:
                print(f"  - {problem}")
            return 1
        print("  ok  multiline arguments indented")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
