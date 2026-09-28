#!/usr/bin/env python3
"""Validate the Cursor rule harness.

The rules are the contract that every agent works from, so a typo in a glob or a
dead cross-reference silently stops a rule from ever loading. This makes that a
build failure instead of a mystery.

Checks:
  1. Every .mdc has well-formed frontmatter with `description` and `alwaysApply`.
  2. Scoped rules declare globs. A glob matching nothing is reported but not fatal —
     several rules deliberately point at directories that arrive with later stories.
  3. Every relative markdown link resolves from the repo root.
  4. No hardcoded TMDB credential in tracked Swift source (see secrets.mdc).

Run from the repo root: python3 scripts/validate-rules.py
"""

from __future__ import annotations

import glob
import os
import re
import subprocess
import sys

RULES_DIR = ".cursor/rules"

# Files still holding a burned key that secrets.mdc says to rotate. Keep empty
# once Globals.swift (or equivalent) is gone; the guard then fails any new leak.
SECRET_DEBT_ALLOWLIST: set[str] = set()

# 32 hex characters: the shape of a TMDB v3 key.
SECRET_PATTERN = re.compile(r"""["'][0-9a-f]{32}["']""")

LINK_PATTERN = re.compile(r"\[`?[^\]`]+`?\]\(([^)]+)\)")


def fail(problems: list[str], message: str) -> None:
    problems.append(message)


def check_rules(problems: list[str]) -> None:
    paths = sorted(glob.glob(f"{RULES_DIR}/*.mdc"))
    if not paths:
        fail(problems, f"no rules found in {RULES_DIR}")
        return

    for path in paths:
        text = open(path, encoding="utf-8").read()
        match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if not match:
            fail(problems, f"{path}: missing or malformed frontmatter")
            continue

        keys = dict(re.findall(r"^(\w+):[ \t]*(.*)$", match.group(1), re.M))
        for required in ("description", "alwaysApply"):
            if not keys.get(required, "").strip():
                fail(problems, f"{path}: frontmatter is missing `{required}`")

        always = keys.get("alwaysApply", "").strip() == "true"
        globs = [g.strip() for g in keys.get("globs", "").split(",") if g.strip()]

        if not always and not globs:
            fail(problems, f"{path}: alwaysApply is false but no globs are declared, so it never loads")

        print(f"  ok  {os.path.basename(path):22} alwaysApply={str(always).lower()}")

        # A glob that matches nothing is printed so a typo is visible, but not fatal.
        for pattern in globs:
            if not glob.glob(pattern, recursive=True):
                print(f"       pending glob `{pattern}` (matches nothing yet)")


def check_links(problems: list[str]) -> None:
    targets = sorted(glob.glob(f"{RULES_DIR}/*.mdc")) + ["AGENTS.md"]
    targets += sorted(glob.glob(".cursor/skills/*/SKILL.md"))
    for path in targets:
        if not os.path.exists(path):
            continue
        for link in LINK_PATTERN.findall(open(path, encoding="utf-8").read()):
            if link.startswith(("http://", "https://", "#", "mailto:")):
                continue
            link = link.split("#", 1)[0]
            if link and not os.path.exists(link):
                fail(problems, f"{path}: broken link -> {link}")


def check_secrets(problems: list[str]) -> None:
    # splitlines, not split: `TheSilverScreen/View Models/` has a space in it.
    tracked = subprocess.run(
        ["git", "ls-files", "*.swift"], capture_output=True, text=True, check=True
    ).stdout.splitlines()

    for path in tracked:
        if not os.path.isfile(path):
            # Deleted locally but not yet staged — skip; HEAD still has the real scan.
            continue
        for lineno, line in enumerate(open(path, encoding="utf-8"), start=1):
            if not SECRET_PATTERN.search(line):
                continue
            if path in SECRET_DEBT_ALLOWLIST:
                print(f"  WARN {path}:{lineno} known committed credential, pending rotation")
                continue
            fail(problems, f"{path}:{lineno}: hardcoded credential in source (see .cursor/rules/secrets.mdc)")


def main() -> int:
    if not os.path.isdir(RULES_DIR):
        print(f"error: run from the repo root ({RULES_DIR} not found)", file=sys.stderr)
        return 2

    problems: list[str] = []

    print("Rules:")
    check_rules(problems)
    print("Links and credentials:")
    check_links(problems)
    check_secrets(problems)

    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("\nHarness valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
