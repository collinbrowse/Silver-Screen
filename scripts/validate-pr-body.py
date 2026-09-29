#!/usr/bin/env python3
"""Validate that a PR body follows .github/pull_request_template.md.

Agents and CI must reject truncated bodies (e.g. Summary + Test plan only).

Usage:
  python3 scripts/validate-pr-body.py < body.md
  python3 scripts/validate-pr-body.py --file path/to/body.md
  python3 scripts/validate-pr-body.py --pr 8
  PR_BODY='...' python3 scripts/validate-pr-body.py
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

REQUIRED_HEADINGS = [
    "Summary",
    "Decision Tree and Rationale",
    "Test Plan",
    "AI Harness notes",
]

# Template checkboxes agents must keep (or equivalent wording).
REQUIRED_TEST_PLAN_MARKERS = [
    re.compile(r"validate-rules\.py", re.I),
    re.compile(r"validate-tests\.py", re.I),
    re.compile(r"validate-pr-body\.py", re.I),
    re.compile(r"xcodebuild test.*TheSilverScreenTests|only-testing:TheSilverScreenTests", re.I),
]

HEADING = re.compile(r"^##[ \t]+(.+?)\s*$", re.M)


def fail(problems: list[str], message: str) -> None:
    problems.append(message)


def load_body(args: argparse.Namespace) -> str:
    if args.pr is not None:
        result = subprocess.run(
            ["gh", "pr", "view", str(args.pr), "--json", "body", "-q", ".body"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise SystemExit(f"gh pr view failed: {result.stderr.strip() or result.stdout}")
        return result.stdout
    if args.file:
        return open(args.file, encoding="utf-8").read()
    env_body = os.environ.get("PR_BODY")
    if env_body is not None:
        return env_body
    if not sys.stdin.isatty():
        return sys.stdin.read()
    raise SystemExit(
        "No PR body provided. Pass --pr, --file, PR_BODY, or pipe the body on stdin."
    )


def section_bodies(text: str) -> dict[str, str]:
    matches = list(HEADING.finditer(text))
    sections: dict[str, str] = {}
    for index, match in enumerate(matches):
        title = match.group(1).strip()
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        sections[title] = text[start:end].strip()
    return sections


def validate(body: str) -> list[str]:
    problems: list[str] = []
    if not body.strip():
        fail(problems, "PR body is empty")
        return problems

    sections = section_bodies(body)
    # Allow minor heading case/spacing differences via casefold match.
    by_fold = {name.casefold(): (name, content) for name, content in sections.items()}

    for required in REQUIRED_HEADINGS:
        hit = by_fold.get(required.casefold())
        if not hit:
            fail(problems, f"missing required heading `## {required}`")
            continue
        _, content = hit
        if not content:
            fail(problems, f"`## {required}` is empty — fill it or write None where allowed")

    test_plan = by_fold.get("test plan")
    if test_plan:
        _, content = test_plan
        for marker in REQUIRED_TEST_PLAN_MARKERS:
            if not marker.search(content):
                fail(
                    problems,
                    f"`## Test Plan` must include template coverage matching /{marker.pattern}/",
                )

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", type=int, help="Pull request number (via gh)")
    parser.add_argument("--file", help="Path to a markdown file containing the PR body")
    args = parser.parse_args()

    body = load_body(args)
    problems = validate(body)

    print("PR body:")
    if problems:
        for problem in problems:
            print(f"  fail  {problem}")
        print("\nFill every section in .github/pull_request_template.md")
        return 1

    print("  ok  required headings and Test Plan gates present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
