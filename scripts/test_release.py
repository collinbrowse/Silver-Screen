#!/usr/bin/env python3
"""Tests for the release version, changelog, and git tag flow."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

import release

VERSION = """// comment
MARKETING_VERSION = 0.1.1
CURRENT_PROJECT_VERSION = 1
"""

CHANGELOG = """# Changelog

## [Unreleased]

- Stars stay in sync.

## [0.1.1] - 2026-09-27

- Baseline.
"""

PBXPROJ = """
C77D45592788B823003D8011 /* Debug */ = {
	isa = XCBuildConfiguration;
	buildSettings = {
		PRODUCT_BUNDLE_IDENTIFIER = com.collinbrowse.thesilverscreen.dev;
		DEVELOPMENT_TEAM = 84XX2W7G34;
	};
	name = Debug;
};
C77D455A2788B823003D8011 /* Release */ = {
	isa = XCBuildConfiguration;
	buildSettings = {
		PRODUCT_BUNDLE_IDENTIFIER = com.collinbrowse.thesilverscreen;
		DEVELOPMENT_TEAM = 84XX2W7G34;
	};
	name = Release;
};
C77D455C2788B823003D8011 /* Debug */ = {
	isa = XCBuildConfiguration;
	buildSettings = {
		MARKETING_VERSION = 1.0;
		CURRENT_PROJECT_VERSION = 1;
		PRODUCT_BUNDLE_IDENTIFIER = com.collinbrowse.thesilverscreen.tests;
	};
	name = Debug;
};
"""

EXPORT = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>84XX2W7G34</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
"""


def git(root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=root, text=True, capture_output=True, check=True
    )
    return result.stdout.strip()


def make_repo(tmp: Path) -> None:
    subprocess.run(["git", "init", "-b", "main"], cwd=tmp, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmp, check=True)
    subprocess.run(["git", "config", "user.name", "Release Test"], cwd=tmp, check=True)
    (tmp / "Version.xcconfig").write_text(VERSION, encoding="utf-8")
    (tmp / "CHANGELOG.md").write_text(CHANGELOG, encoding="utf-8")
    (tmp / "Config.xcconfig").write_text('#include "Version.xcconfig"\n', encoding="utf-8")
    project = tmp / "TheSilverScreen.xcodeproj"
    project.mkdir()
    (project / "project.pbxproj").write_text(PBXPROJ, encoding="utf-8")
    dist = tmp / "distribution"
    dist.mkdir()
    (dist / "ExportOptions.plist").write_text(EXPORT, encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=tmp, check=True)
    subprocess.run(["git", "commit", "-m", "init"], cwd=tmp, check=True, capture_output=True)


class VersionTests(unittest.TestCase):
    def test_parse_and_bump(self) -> None:
        version = release.parse_version(VERSION)
        self.assertEqual(version, release.Version("0.1.1", 1))
        self.assertEqual(release.bump_marketing(version, "patch"), release.Version("0.1.2", 1))
        self.assertEqual(release.bump_marketing(version, "minor"), release.Version("0.2.0", 1))
        self.assertEqual(release.bump_marketing(version, "major"), release.Version("1.0.0", 1))
        self.assertEqual(release.next_build(version).testflight_tag, "testflight/0.1.1+2")
        self.assertEqual(version.appstore_tag, "v0.1.1")

    def test_patch_carries_two_digits(self) -> None:
        version = release.Version("0.1.9", 4)
        self.assertEqual(release.bump_marketing(version, "patch").marketing, "0.1.10")

    def test_rejects_prerelease_and_zero_build(self) -> None:
        with self.assertRaises(release.ReleaseError):
            release.parse_version("MARKETING_VERSION = 1.2.3-beta\nCURRENT_PROJECT_VERSION = 1\n")
        with self.assertRaises(release.ReleaseError):
            release.parse_version("MARKETING_VERSION = 1.2\nCURRENT_PROJECT_VERSION = 1\n")
        with self.assertRaises(release.ReleaseError):
            release.parse_version("MARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 0\n")

    def test_render_replaces_values_and_keeps_comments(self) -> None:
        rendered = release.render_version(VERSION, release.Version("1.4.0", 12))
        self.assertIn("// comment", rendered)
        self.assertEqual(release.parse_version(rendered), release.Version("1.4.0", 12))


class ChangelogTests(unittest.TestCase):
    def test_cut_moves_unreleased_notes(self) -> None:
        updated, notes = release.changelog_after_cut(CHANGELOG, release.Version("0.1.1", 2), "2026-09-27")
        self.assertEqual(notes, "- Stars stay in sync.")
        self.assertIn("## [0.1.1+2] - 2026-09-27\n\n- Stars stay in sync.", updated)
        self.assertIn("## [0.1.1] - 2026-09-27", updated)
        _, body, _ = release.split_unreleased(updated)
        self.assertEqual(release.meaningful_notes(body), "")

    def test_empty_unreleased_still_cuts(self) -> None:
        text = "# Changelog\n\n## [Unreleased]\n\n<!-- placeholder -->\n"
        updated, notes = release.changelog_after_cut(text, release.Version("0.2.0", 3), "2026-10-01")
        self.assertEqual(notes, "- No notes recorded.")
        self.assertIn("## [0.2.0+3] - 2026-10-01", updated)

    def test_missing_unreleased_section_fails(self) -> None:
        with self.assertRaises(release.ReleaseError):
            release.split_unreleased("# Changelog\n\n## [0.1.1]\n")


class ProjectTests(unittest.TestCase):
    def test_app_target_version_override_fails_and_tests_do_not(self) -> None:
        self.assertEqual(release.version_overrides(PBXPROJ), [])
        drifted = PBXPROJ.replace(
            "PRODUCT_BUNDLE_IDENTIFIER = com.collinbrowse.thesilverscreen.dev;",
            "MARKETING_VERSION = 9.9.9;\n\t\tPRODUCT_BUNDLE_IDENTIFIER = com.collinbrowse.thesilverscreen.dev;",
        )
        problems = release.version_overrides(drifted)
        self.assertEqual(len(problems), 1)
        self.assertIn("MARKETING_VERSION", problems[0])

    def test_workspace_release_files_agree(self) -> None:
        root = Path(__file__).resolve().parents[1]
        self.assertEqual(release.collect_problems(root), [])


class GitFlowTests(unittest.TestCase):
    def test_cut_promote_and_retarget(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            make_repo(root)

            first = release.cmd_cut(root, "main", "2026-09-27")
            self.assertIn("testflight/0.1.1+2", first)
            self.assertEqual(release.parse_version((root / "Version.xcconfig").read_text()), release.Version("0.1.1", 2))
            self.assertEqual(git(root, "rev-parse", "HEAD"), git(root, "rev-parse", "testflight/0.1.1+2^{}"))
            committed = {
                line for line in git(root, "show", "--name-only", "--format=", "HEAD").splitlines() if line
            }
            self.assertEqual(committed, {"CHANGELOG.md", "Version.xcconfig"})

            with self.assertRaises(release.ReleaseError):
                release.cmd_cut(root, "main", "2026-09-27")

            release.cmd_promote(root, retarget=False)
            self.assertEqual(
                git(root, "rev-parse", "v0.1.1^{}"),
                git(root, "rev-parse", "testflight/0.1.1+2^{}"),
            )

            (root / "CHANGELOG.md").write_text(
                (root / "CHANGELOG.md").read_text().replace(
                    "## [Unreleased]\n", "## [Unreleased]\n\n- Fix playback.\n", 1
                ),
                encoding="utf-8",
            )
            subprocess.run(["git", "add", "CHANGELOG.md"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-m", "Fix playback."], cwd=root, check=True, capture_output=True)

            release.cmd_cut(root, "main", "2026-09-28")
            with self.assertRaises(release.ReleaseError):
                release.cmd_promote(root, retarget=False)
            moved = release.cmd_promote(root, retarget=True)
            self.assertIn("--force", moved)
            self.assertEqual(
                git(root, "rev-parse", "v0.1.1^{}"),
                git(root, "rev-parse", "testflight/0.1.1+3^{}"),
            )

    def test_cut_refuses_a_dirty_tree_and_the_wrong_branch(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            make_repo(root)
            (root / "notes.txt").write_text("dirty\n", encoding="utf-8")
            with self.assertRaises(release.ReleaseError):
                release.cmd_cut(root, "main", "2026-09-27")
            self.assertEqual(release.parse_version((root / "Version.xcconfig").read_text()).build, 1)

            subprocess.run(["git", "checkout", "-b", "feature"], cwd=root, check=True, capture_output=True)
            (root / "notes.txt").unlink()
            with self.assertRaises(release.ReleaseError):
                release.cmd_cut(root, "main", "2026-09-27")
            release.cmd_cut(root, "feature", "2026-09-27")
            self.assertEqual(release.parse_version((root / "Version.xcconfig").read_text()).build, 2)


if __name__ == "__main__":
    unittest.main()
