#!/usr/bin/env python3
"""Versions, tags, and archives for dev, TestFlight, and the App Store.

Version.xcconfig is the only shipping version. Dev runs do not advance it.
`cut` commits the next build and tags testflight/<marketing>+<build>. `promote`
puts v<marketing> on that same commit so the App Store submission is the
binary already on TestFlight.

Run from the repo root: python3 scripts/release.py status
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

APP_BUNDLE_IDS = frozenset(
    {
        "com.collinbrowse.thesilverscreen",
        "com.collinbrowse.thesilverscreen.dev",
    }
)

MARKETING_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
BUILD_RE = re.compile(r"^[1-9]\d*$")
SETTING_RE = re.compile(r"^(?P<key>MARKETING_VERSION|CURRENT_PROJECT_VERSION)\s*=\s*(?P<value>.+?)\s*$", re.M)


class ReleaseError(Exception):
    """A release step the caller can fix. Printed as the command's error."""


@dataclass(frozen=True)
class Version:
    """Marketing version plus the upload counter those two channels share."""

    marketing: str
    build: int

    @property
    def testflight_tag(self) -> str:
        return f"testflight/{self.marketing}+{self.build}"

    @property
    def appstore_tag(self) -> str:
        return f"v{self.marketing}"

    def label(self) -> str:
        return f"{self.marketing} ({self.build})"


def parse_version(text: str) -> Version:
    """Read both settings. A missing or malformed value is a release error."""
    found = {match.group("key"): match.group("value") for match in SETTING_RE.finditer(text)}
    marketing = found.get("MARKETING_VERSION", "")
    build = found.get("CURRENT_PROJECT_VERSION", "")
    if not MARKETING_RE.fullmatch(marketing):
        raise ReleaseError(
            f"MARKETING_VERSION must be major.minor.patch (three integers). Found {marketing!r}."
        )
    if not BUILD_RE.fullmatch(build):
        raise ReleaseError(
            f"CURRENT_PROJECT_VERSION must be a positive integer. Found {build!r}."
        )
    return Version(marketing, int(build))


def replace_setting(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"^({re.escape(key)}\s*=\s*)(.+?)\s*$", re.M)
    updated, count = pattern.subn(rf"\g<1>{value}", text, count=1)
    if count != 1:
        raise ReleaseError(f"Version.xcconfig is missing {key}.")
    return updated


def render_version(text: str, version: Version) -> str:
    updated = replace_setting(text, "MARKETING_VERSION", version.marketing)
    return replace_setting(updated, "CURRENT_PROJECT_VERSION", str(version.build))


def bump_marketing(version: Version, kind: str) -> Version:
    """Advance major, minor, or patch. The build counter stays where it is."""
    major, minor, patch = (int(part) for part in version.marketing.split("."))
    if kind == "patch":
        marketing = f"{major}.{minor}.{patch + 1}"
    elif kind == "minor":
        marketing = f"{major}.{minor + 1}.0"
    elif kind == "major":
        marketing = f"{major + 1}.0.0"
    else:
        raise ReleaseError(f"Unknown bump {kind!r}. Use patch, minor, or major.")
    return Version(marketing, version.build)


def next_build(version: Version) -> Version:
    return Version(version.marketing, version.build + 1)


def split_unreleased(text: str) -> tuple[str, str, str]:
    """Split a changelog into (through the Unreleased header, its body, the rest)."""
    lines = text.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.startswith("## [Unreleased]")), None)
    if start is None:
        raise ReleaseError("CHANGELOG.md needs a ## [Unreleased] section.")
    end = next((j for j in range(start + 1, len(lines)) if lines[j].startswith("## ")), len(lines))
    before = "".join(lines[: start + 1])
    body = "".join(lines[start + 1 : end])
    after = "".join(lines[end:])
    return before, body, after


def meaningful_notes(body: str) -> str:
    """Drop blank lines and whole-line HTML comments. What remains is the cut note."""
    kept: list[str] = []
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped or (stripped.startswith("<!--") and stripped.endswith("-->")):
            continue
        kept.append(line.rstrip())
    return "\n".join(kept).strip()


def changelog_after_cut(text: str, version: Version, today: str) -> tuple[str, str]:
    """Move Unreleased notes under version+build. Returns (changelog, notes)."""
    before, body, after = split_unreleased(text)
    notes = meaningful_notes(body) or "- No notes recorded."
    section = f"## [{version.marketing}+{version.build}] - {today}\n\n{notes}\n\n"
    updated = before.rstrip("\n") + "\n\n" + section + after.lstrip("\n")
    if not updated.endswith("\n"):
        updated += "\n"
    return updated, notes


def _brace_block(text: str, open_index: int) -> str:
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[open_index : index + 1]
    raise ReleaseError("project.pbxproj has an unclosed build configuration.")


def configuration_bodies(text: str) -> list[str]:
    bodies: list[str] = []
    needle = "isa = XCBuildConfiguration;"
    start = 0
    while True:
        found = text.find(needle, start)
        if found < 0:
            break
        brace = text.rfind("{", 0, found)
        if brace < 0:
            raise ReleaseError("project.pbxproj has a build configuration without an opening brace.")
        bodies.append(_brace_block(text, brace))
        start = found + len(needle)
    return bodies


def _bundle_identifier(body: str) -> str | None:
    match = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", body)
    if not match:
        return None
    return match.group(1).strip().strip('"')


def version_overrides(pbxproj: str) -> list[str]:
    """App-target settings that would shadow Version.xcconfig.

    Both bundle ids must exist: Debug is the dev app, Release is the
    TestFlight and App Store app. Test targets are ignored.
    """
    problems: list[str] = []
    found: set[str] = set()
    for body in configuration_bodies(pbxproj):
        identifier = _bundle_identifier(body)
        if identifier not in APP_BUNDLE_IDS:
            continue
        found.add(identifier)
        for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
            if re.search(rf"^\s*{key}\s*=", body, re.M):
                problems.append(
                    f"{identifier} sets {key} in project.pbxproj. "
                    "Set it in Version.xcconfig only."
                )
    missing = APP_BUNDLE_IDS - found
    if missing:
        problems.append(
            "project.pbxproj is missing the app bundle id " + ", ".join(sorted(missing)) + "."
        )
    return problems


def collect_problems(root: Path) -> list[str]:
    """File-level release invariants. Empty means `check` passes."""
    problems: list[str] = []

    version_path = root / "Version.xcconfig"
    if not version_path.is_file():
        problems.append("Version.xcconfig is missing.")
    else:
        try:
            parse_version(version_path.read_text(encoding="utf-8"))
        except ReleaseError as error:
            problems.append(str(error))

    changelog = root / "CHANGELOG.md"
    if not changelog.is_file():
        problems.append("CHANGELOG.md is missing.")
    else:
        try:
            split_unreleased(changelog.read_text(encoding="utf-8"))
        except ReleaseError as error:
            problems.append(str(error))

    config = root / "Config.xcconfig"
    if not config.is_file():
        problems.append("Config.xcconfig is missing.")
    elif not re.search(r'#include\s+"Version\.xcconfig"', config.read_text(encoding="utf-8")):
        problems.append('Config.xcconfig must #include "Version.xcconfig".')

    pbxproj = root / "TheSilverScreen.xcodeproj" / "project.pbxproj"
    if not pbxproj.is_file():
        problems.append("TheSilverScreen.xcodeproj/project.pbxproj is missing.")
        return problems

    project = pbxproj.read_text(encoding="utf-8")
    problems.extend(version_overrides(project))
    teams = set(re.findall(r"DEVELOPMENT_TEAM = ([A-Z0-9]+);", project))

    export_path = root / "distribution" / "ExportOptions.plist"
    if not export_path.is_file():
        problems.append("distribution/ExportOptions.plist is missing.")
        return problems

    with export_path.open("rb") as handle:
        export = plistlib.load(handle)
    team = export.get("teamID")
    if teams and team not in teams:
        problems.append(
            f"ExportOptions teamID {team} does not match DEVELOPMENT_TEAM "
            f"({', '.join(sorted(teams))})."
        )
    if export.get("manageAppVersionAndBuildNumber") is not False:
        problems.append(
            "ExportOptions must set manageAppVersionAndBuildNumber to false "
            "so export keeps Version.xcconfig."
        )
    if export.get("method") != "app-store-connect":
        problems.append("ExportOptions method must be app-store-connect.")
    return problems


def git(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=root,
        text=True,
        capture_output=True,
        check=check,
    )


def current_branch(root: Path) -> str:
    return git(root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()


def head_commit(root: Path) -> str:
    return git(root, "rev-parse", "HEAD").stdout.strip()


def tag_commit(root: Path, tag: str) -> str | None:
    """Commit an annotated tag points at, or None when the tag is absent."""
    result = git(root, "rev-parse", "--verify", f"{tag}^{{}}", check=False)
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def ensure_clean(root: Path) -> None:
    status = git(root, "status", "--porcelain").stdout
    if status.strip():
        raise ReleaseError("Commit or stash local changes first.\n" + status.rstrip())


def ensure_testflight_head(root: Path, version: Version) -> str:
    """HEAD is the cut commit for this version and build. Returns that SHA."""
    tagged = tag_commit(root, version.testflight_tag)
    head = head_commit(root)
    if tagged is None:
        raise ReleaseError(
            f"Tag {version.testflight_tag} does not exist. Run cut before archive or promote."
        )
    if tagged != head:
        raise ReleaseError(
            f"HEAD is {head[:7]}, and {version.testflight_tag} is {tagged[:7]}. "
            f"Check out the tag: git checkout {version.testflight_tag}"
        )
    return head


def version_at(root: Path, rev: str) -> Version:
    show = git(root, "show", f"{rev}:Version.xcconfig")
    return parse_version(show.stdout)


def recent_tags(root: Path, pattern: str) -> list[str]:
    result = git(root, "tag", "-l", pattern, "--sort=-creatordate")
    return [line for line in result.stdout.splitlines() if line]


def load_version(root: Path) -> tuple[str, Version]:
    path = root / "Version.xcconfig"
    text = path.read_text(encoding="utf-8")
    return text, parse_version(text)


def render_status(root: Path) -> str:
    _, version = load_version(root)
    upcoming = next_build(version)
    branch = current_branch(root)
    head = head_commit(root)
    lines = [
        f"Version {version.label()}",
        f"Branch {branch}",
        "Dev runs use com.collinbrowse.thesilverscreen.dev and leave this number alone.",
        f"Next TestFlight cut uploads {upcoming.label()} as {upcoming.testflight_tag}.",
    ]

    tagged = tag_commit(root, version.testflight_tag)
    if tagged is None:
        lines.append(f"Build {version.build} has not been cut.")
    elif tagged == head:
        lines.append(f"HEAD is {version.testflight_tag}. Archive this commit.")
    else:
        lines.append(f"{version.testflight_tag} is {tagged[:7]}, not HEAD.")

    store = tag_commit(root, version.appstore_tag)
    if store is None:
        lines.append(f"{version.appstore_tag} is not promoted.")
    elif tagged is not None and store == tagged:
        lines.append(
            f"{version.appstore_tag} is the same commit as {version.testflight_tag}. "
            "Submit that build in App Store Connect."
        )
    else:
        lines.append(f"{version.appstore_tag} is {store[:7]}.")

    testflight_tags = recent_tags(root, "testflight/*")
    store_tags = recent_tags(root, "v*")
    if testflight_tags:
        lines.append("Recent TestFlight tags: " + ", ".join(testflight_tags[:5]))
    if store_tags:
        lines.append("Recent App Store tags: " + ", ".join(store_tags[:5]))
    return "\n".join(lines) + "\n"


def render_notes(root: Path) -> str:
    _, body, _ = split_unreleased((root / "CHANGELOG.md").read_text(encoding="utf-8"))
    notes = meaningful_notes(body) or "(empty — the next cut will record that)"
    tags = recent_tags(root, "testflight/*")
    if tags:
        log = git(root, "log", "--oneline", f"{tags[0]}..HEAD").stdout.strip()
        since = f"Commits since {tags[0]}"
    else:
        log = git(root, "log", "--oneline", "-20").stdout.strip()
        since = "Recent commits"
    if not log:
        log = "(none)"
    return f"Unreleased\n{notes}\n\n{since}\n{log}\n"


def require_valid(root: Path) -> None:
    problems = collect_problems(root)
    if problems:
        raise ReleaseError("\n".join(problems))


def cmd_bump(root: Path, kind: str) -> str:
    require_valid(root)
    text, version = load_version(root)
    updated = bump_marketing(version, kind)
    (root / "Version.xcconfig").write_text(render_version(text, updated), encoding="utf-8")
    return (
        f"Marketing version is {updated.marketing}. Build stays {updated.build}.\n"
        f"Commit Version.xcconfig with the work it belongs to. "
        f"The next cut uploads {next_build(updated).label()}.\n"
    )


def cmd_cut(root: Path, branch: str, today: str) -> str:
    """Commit the next build and tag it for TestFlight. Does not push."""
    require_valid(root)
    ensure_clean(root)
    current = current_branch(root)
    if current == "HEAD":
        raise ReleaseError("Cut from a branch. A detached tag already has a build number.")
    if current != branch:
        raise ReleaseError(
            f"On {current}. Cut from {branch}, or pass --branch {current} for a hotfix."
        )

    head = head_commit(root)
    existing = recent_tags(root, "testflight/*")
    for tag in existing:
        if tag_commit(root, tag) == head:
            raise ReleaseError(
                f"HEAD is already {tag}. Archive it, or commit a fix and cut again."
            )

    text, version = load_version(root)
    cut_version = next_build(version)
    if tag_commit(root, cut_version.testflight_tag) is not None:
        raise ReleaseError(f"{cut_version.testflight_tag} already exists.")

    changelog_path = root / "CHANGELOG.md"
    changelog, notes = changelog_after_cut(
        changelog_path.read_text(encoding="utf-8"), cut_version, today
    )
    (root / "Version.xcconfig").write_text(render_version(text, cut_version), encoding="utf-8")
    changelog_path.write_text(changelog, encoding="utf-8")

    git(root, "add", "--", "Version.xcconfig", "CHANGELOG.md")
    message = (
        f"Cut {cut_version.label()} for TestFlight.\n\n"
        f"Archive this commit and upload it. The tag is {cut_version.testflight_tag}."
    )
    commit = git(root, "commit", "-m", message, check=False)
    if commit.returncode != 0:
        raise ReleaseError(commit.stderr.strip() or "git commit failed.")

    tag_message = f"TestFlight {cut_version.label()}\n\n{notes}"
    tagged = git(root, "tag", "-a", cut_version.testflight_tag, "-m", tag_message, check=False)
    if tagged.returncode != 0:
        raise ReleaseError(tagged.stderr.strip() or "git tag failed.")

    return (
        f"Cut {cut_version.label()} as {cut_version.testflight_tag}.\n"
        f"Push when you are ready:\n"
        f"  git push origin {branch}\n"
        f"  git push origin {cut_version.testflight_tag}\n"
        f"Then archive that commit:\n"
        f"  python3 scripts/release.py archive --upload\n"
    )


def cmd_promote(root: Path, retarget: bool) -> str:
    """Point the App Store tag at the current TestFlight commit. Does not archive."""
    require_valid(root)
    ensure_clean(root)
    _, version = load_version(root)
    head = ensure_testflight_head(root, version)
    existing = tag_commit(root, version.appstore_tag)

    if existing == head:
        return (
            f"{version.appstore_tag} already points at this commit. "
            "Submit this build in App Store Connect.\n"
        )

    if existing is not None and not retarget:
        previous = version_at(root, version.appstore_tag)
        raise ReleaseError(
            f"{version.appstore_tag} already points at build {previous.build}. "
            "After a new TestFlight cut of this marketing version, "
            "run promote --retarget."
        )

    if existing is not None:
        previous = version_at(root, version.appstore_tag)
        if version.marketing != previous.marketing or version.build <= previous.build:
            raise ReleaseError(
                f"{version.appstore_tag} is already build {previous.build}. "
                "Retarget only moves it to a newer build of the same marketing version."
            )
        deleted = git(root, "tag", "-d", version.appstore_tag, check=False)
        if deleted.returncode != 0:
            raise ReleaseError(deleted.stderr.strip() or "Could not replace the local tag.")

    message = (
        f"App Store {version.label()}.\n\n"
        f"Same commit as {version.testflight_tag}. "
        "Submit that build in App Store Connect."
    )
    tagged = git(root, "tag", "-a", version.appstore_tag, "-m", message, check=False)
    if tagged.returncode != 0:
        raise ReleaseError(tagged.stderr.strip() or "git tag failed.")

    follow = (
        f"Local tag moved. Push it with: git push origin {version.appstore_tag} --force\n"
        if existing is not None
        else f"Push it with: git push origin {version.appstore_tag}\n"
    )
    return (
        f"{version.appstore_tag} is {head[:7]}, the same commit as {version.testflight_tag}.\n"
        + follow
        + "In App Store Connect, select this build and submit it. Do not archive again.\n"
    )


def _run_visible(cmd: list[str], root: Path, env: dict[str, str] | None = None) -> None:
    print("+ " + " ".join(cmd), flush=True)
    result = subprocess.run(cmd, cwd=root, env=env)
    if result.returncode != 0:
        raise ReleaseError(f"Command failed ({result.returncode}).")


def _upload_command(ipa: Path) -> tuple[list[str], dict[str, str]]:
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
    missing = [name for name, value in (("ASC_KEY_ID", key_id), ("ASC_ISSUER_ID", issuer)) if not value]
    if missing:
        raise ReleaseError(
            "Set "
            + " and ".join(missing)
            + ". Put AuthKey_<ASC_KEY_ID>.p8 in ~/private_keys, ~/.private_keys, "
            "~/.appstoreconnect/private_keys, or point ASC_KEY_PATH at the file."
        )

    env = os.environ.copy()
    key_path = os.environ.get("ASC_KEY_PATH", "").strip()
    if key_path:
        env["API_PRIVATE_KEYS_DIR"] = str(Path(key_path).expanduser().resolve().parent)

    found = subprocess.run(["xcrun", "--find", "altool"], capture_output=True, text=True)
    if found.returncode == 0:
        command = [
            "xcrun",
            "altool",
            "--upload-app",
            "-f",
            str(ipa),
            "-t",
            "ios",
            "--apiKey",
            key_id,
            "--apiIssuer",
            issuer,
        ]
    else:
        command = [
            "xcrun",
            "iTMSTransporter",
            "-m",
            "upload",
            "-assetFile",
            str(ipa),
            "-apiKey",
            key_id,
            "-apiIssuer",
            issuer,
        ]
    return command, env


def _verify_archive(archive: Path, version: Version) -> None:
    info_path = archive / "Products" / "Applications" / "TheSilverScreen.app" / "Info.plist"
    if not info_path.is_file():
        raise ReleaseError(f"Archive is missing {info_path}.")
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    marketing = str(info.get("CFBundleShortVersionString", ""))
    build = str(info.get("CFBundleVersion", ""))
    if marketing != version.marketing or build != str(version.build):
        raise ReleaseError(
            f"The archive is {marketing} ({build}). Version.xcconfig is {version.label()}."
        )


def cmd_archive(root: Path, upload: bool) -> str:
    """Archive the TestFlight tag's commit and optionally upload the IPA."""
    require_valid(root)
    ensure_clean(root)
    _, version = load_version(root)
    ensure_testflight_head(root, version)

    archive = root / "build" / "TheSilverScreen.xcarchive"
    export_dir = root / "build" / "export"
    if archive.exists():
        shutil.rmtree(archive)
    if export_dir.exists():
        shutil.rmtree(export_dir)

    _run_visible(
        [
            "xcodebuild",
            "archive",
            "-project",
            "TheSilverScreen.xcodeproj",
            "-scheme",
            "TheSilverScreen",
            "-configuration",
            "Release",
            "-destination",
            "generic/platform=iOS",
            "-archivePath",
            str(archive),
            "-allowProvisioningUpdates",
        ],
        root,
    )
    _verify_archive(archive, version)
    _run_visible(
        [
            "xcodebuild",
            "-exportArchive",
            "-archivePath",
            str(archive),
            "-exportPath",
            str(export_dir),
            "-exportOptionsPlist",
            "distribution/ExportOptions.plist",
            "-allowProvisioningUpdates",
        ],
        root,
    )

    ipa = export_dir / "TheSilverScreen.ipa"
    if not ipa.is_file():
        found = list(export_dir.glob("*.ipa"))
        if len(found) != 1:
            raise ReleaseError(f"Export did not produce an IPA in {export_dir}.")
        ipa = found[0]

    if upload:
        command, env = _upload_command(ipa)
        _run_visible(command, root, env)
        return f"Uploaded {ipa.name} for {version.label()}. It will show up in TestFlight after processing.\n"

    return (
        f"Exported {ipa} for {version.label()}.\n"
        "Upload with: python3 scripts/release.py archive --upload\n"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="Show the version, branch, and release tags.")
    sub.add_parser("notes", help="Show Unreleased notes and commits since the last TestFlight tag.")
    sub.add_parser("check", help="Fail if version files and the Xcode project disagree.")

    bump = sub.add_parser("bump", help="Advance the marketing version. Does not commit.")
    bump.add_argument("kind", choices=("patch", "minor", "major"))

    cut = sub.add_parser("cut", help="Commit the next build and tag it for TestFlight.")
    cut.add_argument(
        "--branch",
        default="main",
        help="Branch this cut must be on. Pass the hotfix branch name when not cutting from main.",
    )

    promote = sub.add_parser("promote", help="Tag this TestFlight commit for the App Store.")
    promote.add_argument(
        "--retarget",
        action="store_true",
        help="Move the local v tag onto a newer TestFlight build of the same marketing version.",
    )

    archive = sub.add_parser("archive", help="Archive the current TestFlight tag.")
    archive.add_argument("--upload", action="store_true", help="Upload the IPA to App Store Connect.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    root = Path.cwd()
    try:
        if args.command == "check":
            require_valid(root)
            print("Release files agree.")
        elif args.command == "status":
            require_valid(root)
            print(render_status(root), end="")
        elif args.command == "notes":
            require_valid(root)
            print(render_notes(root), end="")
        elif args.command == "bump":
            print(cmd_bump(root, args.kind), end="")
        elif args.command == "cut":
            from datetime import date

            print(cmd_cut(root, args.branch, date.today().isoformat()), end="")
        elif args.command == "promote":
            print(cmd_promote(root, args.retarget), end="")
        elif args.command == "archive":
            print(cmd_archive(root, args.upload), end="")
        else:
            parser.error(f"unknown command {args.command}")
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
