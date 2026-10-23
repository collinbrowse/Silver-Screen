#!/usr/bin/env python3
"""Validate the Claude Code harness.

The rules are the contract that every agent works from, so a typo in a glob or a
dead cross-reference silently stops a rule from ever loading. This makes that a
build failure instead of a mystery.

Checks:
  1. Every .claude/rules/*.md either has no frontmatter (always loaded) or
     well-formed frontmatter whose `paths` is a non-empty list. A glob matching
     nothing is reported but not fatal — several rules deliberately point at
     directories that arrive with later stories.
  2. Every relative markdown link in CLAUDE.md, the rules, and the skills
     resolves from the repo root.
  3. .claude/settings.json parses, and every hook script it names exists and is
     executable.
  4. No hardcoded TMDB credential in tracked Swift source (see secrets.md):
     a 32-hex v3 key, or a JWT-shaped read access token.
  5. Remote Swift packages in the Xcode project are only the approved Sentry repo
     (see observability.md).

Run from the repo root: python3 scripts/validate-rules.py
"""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys

RULES_DIR = ".claude/rules"
SETTINGS = ".claude/settings.json"
PBXPROJ = "SilverScreen.xcodeproj/project.pbxproj"

# Tracked Swift must not contain a TMDB credential. The allowlist stays empty;
# a hit is a new leak.
SECRET_DEBT_ALLOWLIST: set[str] = set()

# 32 hex characters: the shape of a TMDB v3 key.
# eyJ… . … . … : the shape of an API Read Access Token (a JWT).
SECRET_PATTERNS = (
    re.compile(r"""["'][0-9a-f]{32}["']"""),
    re.compile(r"""["']eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}["']"""),
)

LINK_PATTERN = re.compile(r"\[`?[^\]`]+`?\]\(([^)]+)\)")
SPM_URL_PATTERN = re.compile(r'repositoryURL\s*=\s*"([^"]+)"')

# Only remote package allowed in project.pbxproj (with or without .git suffix).
ALLOWED_SPM_REPOS = frozenset(
    {
        "https://github.com/getsentry/sentry-cocoa",
        "https://github.com/getsentry/sentry-cocoa.git",
    }
)


def fail(problems: list[str], message: str) -> None:
    problems.append(message)


def check_rules(problems: list[str]) -> None:
    paths = sorted(glob.glob(f"{RULES_DIR}/**/*.md", recursive=True))
    if not paths:
        fail(problems, f"no rules found in {RULES_DIR}")
        return

    for path in paths:
        text = open(path, encoding="utf-8").read()
        name = os.path.relpath(path, RULES_DIR)
        if not text.startswith("---\n"):
            print(f"  ok  {name:22} always loaded")
            continue

        match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if not match:
            fail(problems, f"{path}: malformed frontmatter")
            continue

        frontmatter = match.group(1)
        if not re.match(r"^paths:[ \t]*$", frontmatter, re.M):
            fail(problems, f"{path}: frontmatter has no `paths` list; drop the frontmatter to load the rule every session")
            continue

        globs = re.findall(r"""^[ \t]+-[ \t]+["']?([^"'\n]+?)["']?[ \t]*$""", frontmatter, re.M)
        if not globs:
            fail(problems, f"{path}: `paths` is empty, so the rule never loads")
            continue

        print(f"  ok  {name:22} paths={len(globs)}")

        # A glob that matches nothing is printed so a typo is visible, but not fatal.
        for pattern in globs:
            if not glob.glob(pattern, recursive=True):
                print(f"       pending glob `{pattern}` (matches nothing yet)")


def check_links(problems: list[str]) -> None:
    targets = sorted(glob.glob(f"{RULES_DIR}/**/*.md", recursive=True)) + ["CLAUDE.md"]
    targets += sorted(glob.glob(".claude/skills/*/SKILL.md"))
    for path in targets:
        if not os.path.exists(path):
            continue
        for link in LINK_PATTERN.findall(open(path, encoding="utf-8").read()):
            if link.startswith(("http://", "https://", "#", "mailto:")):
                continue
            link = link.split("#", 1)[0]
            if link and not os.path.exists(link):
                fail(problems, f"{path}: broken link -> {link}")


def check_hooks(problems: list[str]) -> None:
    """Fail if settings.json is not valid JSON or names a hook script that is missing."""
    if not os.path.isfile(SETTINGS):
        fail(problems, f"{SETTINGS}: missing")
        return
    try:
        settings = json.load(open(SETTINGS, encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(problems, f"{SETTINGS}: invalid JSON ({error})")
        return

    for event, groups in (settings.get("hooks") or {}).items():
        for group in groups:
            for hook in group.get("hooks", []):
                command = hook.get("command", "")
                script = command.replace('"${CLAUDE_PROJECT_DIR}"/', "").replace("${CLAUDE_PROJECT_DIR}/", "").split()[0]
                if not os.path.isfile(script):
                    fail(problems, f"{SETTINGS}: {event} hook script {script!r} does not exist")
                elif not os.access(script, os.X_OK):
                    fail(problems, f"{SETTINGS}: {event} hook script {script!r} is not executable")
                else:
                    print(f"  ok  {event:22} {script}")


def check_secrets(problems: list[str]) -> None:
    # splitlines, not split: `SilverScreen/View Models/` has a space in it.
    tracked = subprocess.run(
        ["git", "ls-files", "*.swift"], capture_output=True, text=True, check=True
    ).stdout.splitlines()

    for path in tracked:
        if not os.path.isfile(path):
            # Deleted locally but not yet staged — skip; HEAD still has the real scan.
            continue
        for lineno, line in enumerate(open(path, encoding="utf-8"), start=1):
            if not any(pattern.search(line) for pattern in SECRET_PATTERNS):
                continue
            if path in SECRET_DEBT_ALLOWLIST:
                print(f"  WARN {path}:{lineno} known committed credential, pending rotation")
                continue
            fail(problems, f"{path}:{lineno}: hardcoded credential in source (see .claude/rules/secrets.md)")


def _normalize_spm_url(url: str) -> str:
    return url.rstrip("/").removesuffix(".git")


def check_spm_packages(problems: list[str]) -> None:
    """Fail if project.pbxproj pulls any remote package other than Sentry."""
    if not os.path.isfile(PBXPROJ):
        fail(problems, f"{PBXPROJ}: missing")
        return

    urls = SPM_URL_PATTERN.findall(open(PBXPROJ, encoding="utf-8").read())
    allowed_normalized = {_normalize_spm_url(url) for url in ALLOWED_SPM_REPOS}
    if not urls:
        print("  ok  no remote Swift packages (Sentry not wired yet)")
        return

    for url in urls:
        if _normalize_spm_url(url) not in allowed_normalized:
            fail(
                problems,
                f"{PBXPROJ}: unapproved Swift package {url!r} "
                "(only https://github.com/getsentry/sentry-cocoa is allowed; see .claude/rules/observability.md)",
            )
        else:
            print(f"  ok  approved package {url}")


def main() -> int:
    if not os.path.isdir(RULES_DIR):
        print(f"error: run from the repo root ({RULES_DIR} not found)", file=sys.stderr)
        return 2

    problems: list[str] = []

    print("Rules:")
    check_rules(problems)
    print("Hooks:")
    check_hooks(problems)
    print("Links and credentials:")
    check_links(problems)
    check_secrets(problems)
    print("Swift packages:")
    check_spm_packages(problems)

    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("\nHarness valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
