#!/usr/bin/env python3
"""Validate that the unit-test suite can be trusted.

Green CI means nothing if tests assert nothing. This script makes that a
build failure.

Checks:
  1. Every `func test...` in TheSilverScreenTests has at least one assertion (or
     XCTFail / throws expectation). Empty bodies and Xcode placeholders fail.
  2. Banned placeholder names (`testExample`, `testPerformanceExample`) never
     appear in TheSilverScreenTests.

Run from the repo root:
  python3 scripts/validate-tests.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

TESTS_ROOT = Path("TheSilverScreenTests")

BANNED_NAMES = {"testExample", "testPerformanceExample"}

# A method counts as asserting if its body mentions one of these.
ASSERTION_MARKERS = re.compile(
    r"XCTAssert|XCTFail|XCTExpect|XCTUnwrap|XCTSkip|#expect\b|assert\("
)

TEST_FUNC = re.compile(
    r"func\s+(test\w+)\s*\([^)]*\)\s*(?:async\s+)?(?:throws\s+)?\{",
    re.MULTILINE,
)


def fail(problems: list[str], message: str) -> None:
    problems.append(message)


def method_body(source: str, brace_start: int) -> str:
    """Return the text between the opening `{` at brace_start and its match."""
    depth = 0
    i = brace_start
    while i < len(source):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return source[brace_start + 1 : i]
        i += 1
    return source[brace_start + 1 :]


def check_test_bodies(problems: list[str]) -> None:
    if not TESTS_ROOT.is_dir():
        fail(problems, f"{TESTS_ROOT}/ is missing")
        return

    swift_files = sorted(TESTS_ROOT.rglob("*.swift"))
    if not swift_files:
        fail(problems, f"{TESTS_ROOT}/ has no Swift files")
        return

    test_count = 0
    for path in swift_files:
        source = path.read_text(encoding="utf-8")
        for match in TEST_FUNC.finditer(source):
            name = match.group(1)
            test_count += 1
            rel = path.as_posix()

            if name in BANNED_NAMES:
                fail(
                    problems,
                    f"{rel}: banned placeholder `{name}` — delete it; "
                    "green CI must not come from empty Xcode templates",
                )
                continue

            body = method_body(source, match.end() - 1)
            stripped = re.sub(r"//.*?$|/\*.*?\*/", "", body, flags=re.M | re.S).strip()
            if not stripped:
                fail(problems, f"{rel}: `{name}` has an empty body")
                continue
            if not ASSERTION_MARKERS.search(body):
                fail(
                    problems,
                    f"{rel}: `{name}` has no assertion "
                    "(need XCTAssert*, XCTFail, XCTUnwrap, or XCTExpect*)",
                )

    if test_count == 0:
        fail(problems, f"{TESTS_ROOT}/ defines no `func test...` methods")
    else:
        print(f"  ok  {test_count} test method(s) under {TESTS_ROOT}/")


def main() -> int:
    problems: list[str] = []

    print("Test bodies:")
    check_test_bodies(problems)

    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("\nTest suite gates valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
