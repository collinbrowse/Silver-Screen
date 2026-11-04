#!/usr/bin/env python3
"""Sync marketing/output/ to App Store Connect: screenshots, the app preview, and
the iOS 27 creative assets (product page header and search results art).

`release.py media` runs this, and `release.py cut` runs it with --apply after it
tags a build. Without apply it only reads App Store Connect and prints what it
would change. Stdlib only, through asc_api.ASCClient.

Two upload paths:

- Classic sets (iPhone 6.9", iPhone 6.3", 13" iPad, and the app preview) go into
  the version localization's appScreenshotSets / appPreviewSets. Apple stores an
  MD5 of each file, so an unchanged set is left alone and a changed one is
  replaced whole, in upload order.
- The Asset Library holds the header, the search art, and iPhone Duo screenshots.
  Library assets carry no checksum, so each upload is named after its content
  hash (silverscreen-header-dark-<sha>.png). An asset already in the library is
  reused, and a placement on the localization points the slot at it.

Apple takes one appearance per slot, so one run uploads either the light or the
dark set. Header and search placements on a version in preparation go live when
that version is approved. On a live version (--live) only an asset App Review
has already approved can be placed, and it shows straight away.
"""

from __future__ import annotations

import hashlib
import struct
import time
from dataclasses import dataclass, field
from pathlib import Path

from asc_api import ASCError


class MediaError(Exception):
    """A media problem the caller can fix: wrong sizes, missing version, upload failure."""


# Local folder under appstore/ → (screenshotDisplayType, pixel size). Apple's names:
# APP_IPHONE_67 is the 6.9" slot, APP_IPHONE_61 the 6.3" one, APP_IPAD_PRO_3GEN_129 13".
SCREENSHOT_SETS = (
    ("iphone", "APP_IPHONE_67", (1320, 2868)),
    ("iphone-6.3", "APP_IPHONE_61", (1206, 2622)),
    ("ipad", "APP_IPAD_PRO_3GEN_129", (2064, 2752)),
)
# The app preview marketing.py cuts (886×1920 fits the 6.9" slot). It is recorded
# in dark only, whatever appearance the screenshots use.
PREVIEW_PATH = Path("video/iphone/dark/appstore-preview.mp4")
PREVIEW_TYPE = "IPHONE_67"
# iPhone Duo screenshots live in the Asset Library, placed in one group. Apple has
# confirmed the outer (folded) set through the API, and one set of up to ten fits
# a group, so one Duo set is uploaded per run.
DUO_SETS = {"outer": ("duo-outer", (1398, 2034)), "inner": ("duo", (2853, 2007))}
DUO_GROUP = "IPHONE_DUO_PROFILE"
DEFAULT_GROUP = "DEFAULT_PROFILE"
HEADER_SIZE = (3840, 1646)
SEARCH_SIZE = (3840, 2560)
MAX_SCREENSHOTS = 10

# appVersionState / appStoreState values whose media can still change.
EDITABLE_STATES = frozenset(
    {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "INVALID_BINARY",
    }
)
LIVE_STATES = frozenset({"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"})
# Library asset states that mean the upload is still being processed.
PROCESSING_STATES = frozenset({"AWAITING_UPLOAD", "UPLOAD_COMPLETE"})
# Library assets in these states cannot be placed, so a new copy is uploaded.
UNUSABLE_STATES = frozenset({"AWAITING_UPLOAD", "FAILED", "ARCHIVED", "REJECTED"})
VIDEO_SUFFIXES = frozenset({".mp4", ".mov", ".m4v"})


@dataclass(frozen=True)
class MediaFile:
    """One local file to upload, with the digests Apple and the library naming need."""

    path: Path
    size: int
    md5: str
    sha256: str

    @classmethod
    def read(cls, path: Path) -> "MediaFile":
        data = path.read_bytes()
        return cls(
            path=path,
            size=len(data),
            md5=hashlib.md5(data).hexdigest(),
            sha256=hashlib.sha256(data).hexdigest(),
        )

    @property
    def is_video(self) -> bool:
        return self.path.suffix.lower() in VIDEO_SUFFIXES

    def library_name(self, stem: str) -> str:
        """Content-addressed name, so the same bytes are never uploaded twice."""
        return f"silverscreen-{stem}-{self.sha256[:12]}{self.path.suffix.lower()}"


@dataclass
class Slot:
    """One App Store media slot and the local files that should fill it, in order.

    kind is "screenshots" or "previews" (classic sets, key = display/preview type)
    or "library" (Asset Library placement, key = placement type, group = profile).
    """

    kind: str
    key: str
    label: str
    files: list[MediaFile]
    group: str | None = None
    category: str = "CREATIVE_ASSETS"
    stem: str = ""
    creative: bool = False


def png_size(path: Path) -> tuple[int, int] | None:
    """Width and height from a PNG's IHDR chunk, or None for a file that is not a PNG."""
    with path.open("rb") as handle:
        head = handle.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def _pngs(folder: Path) -> list[Path]:
    return sorted(path for path in folder.glob("*.png") if path.is_file()) if folder.is_dir() else []


def collect_slots(output: Path, appearance: str, duo: str = "outer") -> tuple[list[Slot], list[str]]:
    """Read marketing/output into slots. Returns (slots, notes about skipped slots).

    A file with the wrong pixel size, or a set over Apple's ten-screenshot limit, is
    a MediaError before anything is uploaded.
    """
    appstore = output / "appstore"
    slots: list[Slot] = []
    notes: list[str] = []
    problems: list[str] = []

    def check(paths: list[Path], size: tuple[int, int]) -> None:
        for path in paths:
            found = png_size(path)
            if found != size:
                shown = "not a PNG" if found is None else f"{found[0]}×{found[1]}"
                problems.append(f"{path} is {shown}, expected {size[0]}×{size[1]}.")
        if len(paths) > MAX_SCREENSHOTS:
            problems.append(f"{paths[0].parent} has {len(paths)} screenshots; Apple takes {MAX_SCREENSHOTS}.")

    for folder, display_type, size in SCREENSHOT_SETS:
        paths = _pngs(appstore / folder / appearance)
        if not paths:
            notes.append(f"No {folder}/{appearance} screenshots; {display_type} left as it is.")
            continue
        check(paths, size)
        slots.append(Slot("screenshots", display_type, f"Screenshots {display_type}", [MediaFile.read(p) for p in paths]))

    preview = output / PREVIEW_PATH
    if preview.is_file():
        slots.append(Slot("previews", PREVIEW_TYPE, f"App preview {PREVIEW_TYPE}", [MediaFile.read(preview)]))
    else:
        notes.append(f"No {PREVIEW_PATH}; the app preview is left as it is.")

    duo_folder, duo_size = DUO_SETS[duo]
    duo_paths = _pngs(appstore / duo_folder / appearance)
    if duo_paths:
        check(duo_paths, duo_size)
        slots.append(
            Slot(
                "library",
                "APP_SCREENSHOT",
                f"iPhone Duo screenshots ({duo})",
                [MediaFile.read(p) for p in duo_paths],
                group=DUO_GROUP,
                category="APP_SCREENSHOTS_AND_PREVIEWS",
                stem=f"{duo_folder}-{appearance}",
            )
        )
    else:
        notes.append(f"No {duo_folder}/{appearance} screenshots; iPhone Duo left as it is.")

    header_dir = appstore / "header"
    motion = header_dir / f"header-motion-{appearance}.mp4"
    still = header_dir / f"header-{appearance}.png"
    header = motion if motion.is_file() else still
    if header.is_file():
        if header == still:
            check([still], HEADER_SIZE)
        slots.append(
            Slot(
                "library",
                "PRODUCT_PAGE_HEADER_ASSET",
                "Product page header" + (" video" if header == motion else ""),
                [MediaFile.read(header)],
                group=DEFAULT_GROUP,
                stem=f"header-{appearance}",
                creative=True,
            )
        )
    else:
        notes.append(f"No header-{appearance} art; the product page header is left as it is.")

    search = header_dir / f"search-{appearance}.png"
    if search.is_file():
        check([search], SEARCH_SIZE)
        slots.append(
            Slot(
                "library",
                "APP_STORE_SEARCH_RESULTS_ASSET",
                "Search results art",
                [MediaFile.read(search)],
                group=DEFAULT_GROUP,
                stem=f"search-{appearance}",
                creative=True,
            )
        )
    else:
        notes.append(f"No search-{appearance} art; the search results asset is left as it is.")

    if problems:
        raise MediaError("Fix these before uploading:\n  " + "\n  ".join(problems))
    return slots, notes


def version_state(row: dict) -> str:
    attributes = row.get("attributes") or {}
    return attributes.get("appVersionState") or attributes.get("appStoreState") or ""


# Classic set resources, keyed by Slot.kind.
_CLASSIC = {
    "screenshots": {
        "sets": "appScreenshotSets",
        "items": "appScreenshots",
        "set_rel": "appScreenshotSet",
        "attribute": "screenshotDisplayType",
    },
    "previews": {
        "sets": "appPreviewSets",
        "items": "appPreviews",
        "set_rel": "appPreviewSet",
        "attribute": "previewType",
    },
}


@dataclass
class MediaSync:
    """Brings one version localization's media in line with the local slots.

    Without apply, every write is logged as "would …" and skipped, so the run is
    a plan. Reads always go out, so the plan reflects what is on App Store Connect.
    """

    client: object
    apply: bool = False
    log: object = print
    sleep: object = time.sleep
    clock: object = time.monotonic
    # Videos commonly take 10 to 15 minutes to process.
    processing_timeout: float = 1800
    poll_interval: float = 15
    failures: list[str] = field(default_factory=list)
    changes: int = 0
    _library_id: str | None = None
    _library_assets: dict | None = None

    # MARK: Version

    def target_version(self, app_id: str, marketing: str, live: bool) -> tuple[str | None, str]:
        """(version id, state) to put media on. None in a plan that would create it.

        The version for this marketing string must be editable. With live, the live
        version is used instead, for header and search art only.
        """
        rows, _ = self.client.get_all(
            f"/v1/apps/{app_id}/appStoreVersions",
            {"filter[platform]": "IOS", "limit": "20"},
        )
        if live:
            for row in rows:
                if version_state(row) in LIVE_STATES:
                    return str(row["id"]), version_state(row)
            raise MediaError("No live App Store version to place header and search art on.")

        for row in rows:
            if (row.get("attributes") or {}).get("versionString") == marketing:
                state = version_state(row)
                if state not in EDITABLE_STATES:
                    raise MediaError(
                        f"App Store version {marketing} is {state}, so its screenshots are locked. "
                        "Header and search art can still change on a live version with --live."
                    )
                return str(row["id"]), state

        for row in rows:
            if version_state(row) in EDITABLE_STATES:
                other = (row.get("attributes") or {}).get("versionString")
                raise MediaError(
                    f"App Store Connect's version in preparation is {other}, not {marketing}. "
                    "Rename or remove it there first."
                )

        self.log(f"Create App Store version {marketing}.")
        if not self.apply:
            return None, "PREPARE_FOR_SUBMISSION"
        created = self.client.request(
            "POST",
            "/v1/appStoreVersions",
            payload={
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {"platform": "IOS", "versionString": marketing},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        )
        self.changes += 1
        return str(created["data"]["id"]), "PREPARE_FOR_SUBMISSION"

    def localization_id(self, version_id: str | None, locale: str) -> str | None:
        if version_id is None:
            return None
        rows, _ = self.client.get_all(
            f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", {"limit": "50"}
        )
        for row in rows:
            if (row.get("attributes") or {}).get("locale") == locale:
                return str(row["id"])
        raise MediaError(f"The App Store version has no {locale} localization.")

    # MARK: Classic sets

    def sync_classic(self, localization: str | None, slot: Slot) -> None:
        spec = _CLASSIC[slot.kind]
        set_id = None
        remote: list[dict] = []
        if localization is not None:
            sets, _ = self.client.get_all(
                f"/v1/appStoreVersionLocalizations/{localization}/{spec['sets']}", {"limit": "50"}
            )
            match = [row for row in sets if (row.get("attributes") or {}).get(spec["attribute"]) == slot.key]
            if match:
                set_id = str(match[0]["id"])
                remote, _ = self.client.get_all(f"/v1/{spec['sets']}/{set_id}/{spec['items']}", {"limit": "50"})

        remote_sums = [(row.get("attributes") or {}).get("sourceFileChecksum") for row in remote]
        failed = any(
            ((row.get("attributes") or {}).get("assetDeliveryState") or {}).get("state") == "FAILED"
            for row in remote
        )
        if remote_sums == [item.md5 for item in slot.files] and not failed:
            self.log(f"{slot.label}: {len(slot.files)} unchanged.")
            return

        self.log(f"{slot.label}: replace {len(remote)} with {len(slot.files)}.")
        self.changes += 1
        if not self.apply:
            return
        if set_id is None:
            created = self.client.request(
                "POST",
                f"/v1/{spec['sets']}",
                payload={
                    "data": {
                        "type": spec["sets"],
                        "attributes": {spec["attribute"]: slot.key},
                        "relationships": {
                            "appStoreVersionLocalization": {
                                "data": {"type": "appStoreVersionLocalizations", "id": localization}
                            }
                        },
                    }
                },
            )
            set_id = str(created["data"]["id"])
        for row in remote:
            self.client.request("DELETE", f"/v1/{spec['items']}/{row['id']}")
        for item in slot.files:
            reserved = self.client.request(
                "POST",
                f"/v1/{spec['items']}",
                payload={
                    "data": {
                        "type": spec["items"],
                        "attributes": {"fileName": item.path.name, "fileSize": item.size},
                        "relationships": {spec["set_rel"]: {"data": {"type": spec["sets"], "id": set_id}}},
                    }
                },
            )
            item_id = str(reserved["data"]["id"])
            operations = (reserved["data"].get("attributes") or {}).get("uploadOperations") or []
            self.client.upload_parts(operations, item.path.read_bytes())
            self.client.request(
                "PATCH",
                f"/v1/{spec['items']}/{item_id}",
                payload={
                    "data": {
                        "type": spec["items"],
                        "id": item_id,
                        "attributes": {"uploaded": True, "sourceFileChecksum": item.md5},
                    }
                },
            )
            self.log(f"  uploaded {item.path.name}")

    # MARK: Asset Library

    def library_id(self, app_id: str) -> str:
        if self._library_id is None:
            data = self.client.request("GET", f"/v1/apps/{app_id}/assetLibrary")
            self._library_id = str((data.get("data") or {})["id"])
        return self._library_id

    def library_assets(self, app_id: str) -> dict:
        """fileName → (resource type, id, state) for every usable library image and video."""
        if self._library_assets is None:
            library = self.library_id(app_id)
            found: dict = {}
            for kind in ("images", "videos"):
                rows, _ = self.client.get_all(f"/v1/appAssetLibraries/{library}/{kind}", {"limit": "50"})
                resource = "appAssetLibraryImages" if kind == "images" else "appAssetLibraryVideos"
                for row in rows:
                    attributes = row.get("attributes") or {}
                    state = attributes.get("state") or ""
                    name = attributes.get("fileName")
                    # Keep an approved copy over a later duplicate still in review.
                    if name and state not in UNUSABLE_STATES and (found.get(name) or ("", "", ""))[2] != "APPROVED":
                        found[name] = (resource, str(row["id"]), state)
            self._library_assets = found
        return self._library_assets

    def ensure_asset(self, app_id: str, slot: Slot, item: MediaFile) -> tuple[str, str]:
        """(resource type, id or placeholder) of the library asset holding item's bytes."""
        name = item.library_name(slot.stem)
        assets = self.library_assets(app_id)
        if name in assets:
            resource, asset_id, state = assets[name]
            if state in PROCESSING_STATES and self.apply:
                # An earlier run timed out before processing finished; placing it now would fail.
                assets[name] = (resource, asset_id, self.wait_processed(resource, asset_id))
            return resource, asset_id

        resource = "appAssetLibraryVideos" if item.is_video else "appAssetLibraryImages"
        self.log(f"  upload {name} to the Asset Library")
        self.changes += 1
        if not self.apply:
            return resource, f"new:{name}"
        reserved = self.client.request(
            "POST",
            f"/v1/{resource}",
            payload={
                "data": {
                    "type": resource,
                    "attributes": {"category": slot.category, "fileName": name, "fileSize": item.size},
                    "relationships": {
                        "assetLibrary": {"data": {"type": "appAssetLibraries", "id": self.library_id(app_id)}}
                    },
                }
            },
        )
        asset_id = str(reserved["data"]["id"])
        operations = (reserved["data"].get("attributes") or {}).get("uploadOperations") or []
        self.client.upload_parts(operations, item.path.read_bytes())
        self.client.request(
            "PATCH",
            f"/v1/{resource}/{asset_id}",
            payload={"data": {"type": resource, "id": asset_id, "attributes": {"uploaded": True}}},
        )
        state = self.wait_processed(resource, asset_id)
        assets[name] = (resource, asset_id, state)
        return resource, asset_id

    def wait_processed(self, resource: str, asset_id: str) -> str:
        """Poll until Apple finishes processing an upload. A placement fails before then."""
        deadline = self.clock() + self.processing_timeout
        while True:
            data = self.client.request("GET", f"/v1/{resource}/{asset_id}")
            attributes = (data.get("data") or {}).get("attributes") or {}
            state = attributes.get("state") or ""
            if state == "FAILED":
                raise MediaError(f"App Store Connect could not process {resource} {asset_id}: {attributes.get('stateDetails')}")
            if state not in PROCESSING_STATES:
                return state
            if self.clock() >= deadline:
                raise MediaError(f"{resource} {asset_id} is still {state}. Rerun once it finishes processing.")
            self.sleep(self.poll_interval)

    def placements(self, localization: str | None) -> list[dict]:
        if localization is None:
            return []
        rows, _ = self.client.get_all(
            f"/v1/appStoreVersionLocalizations/{localization}/placements",
            {"include": "image,video", "limit": "50"},
        )
        return rows

    @staticmethod
    def placement_asset(row: dict) -> str | None:
        relationships = row.get("relationships") or {}
        for key in ("image", "video"):
            data = (relationships.get(key) or {}).get("data")
            if data:
                return str(data["id"])
        return None

    def sync_library(self, app_id: str, localization: str | None, slot: Slot, current: list[dict], live: bool) -> None:
        if live:
            # A live version takes only approved assets, and shows them at once.
            unapproved = []
            for item in slot.files:
                entry = self.library_assets(app_id).get(item.library_name(slot.stem))
                if entry is None or entry[2] != "APPROVED":
                    unapproved.append(item.library_name(slot.stem))
            if unapproved:
                self.log(
                    f"{slot.label}: not placed on the live version until App Review approves "
                    + ", ".join(unapproved)
                    + ". Upload with a version, or submit it from the Asset Library."
                )
                for item in slot.files:
                    self.ensure_asset(app_id, slot, item)
                return

        mine = [
            row
            for row in current
            if (row.get("attributes") or {}).get("placementType") == slot.key
            and (row.get("attributes") or {}).get("placementGroup") in (None, slot.group)
        ]
        wanted = [self.ensure_asset(app_id, slot, item) for item in slot.files]
        if [self.placement_asset(row) for row in mine] == [asset_id for _, asset_id in wanted]:
            self.log(f"{slot.label}: unchanged.")
            return

        self.log(f"{slot.label}: place {len(wanted)}" + (f", replacing {len(mine)}." if mine else "."))
        self.changes += 1
        if not self.apply:
            return
        # A slot holds its own assets only, and placements cannot be edited.
        for row in mine:
            self.client.request("DELETE", f"/v1/appAssetLibraryPlacements/{row['id']}")
        for resource, asset_id in wanted:
            relationship = "video" if resource == "appAssetLibraryVideos" else "image"
            self.client.request(
                "POST",
                "/v1/appAssetLibraryPlacements",
                payload={
                    "data": {
                        "type": "appAssetLibraryPlacements",
                        "attributes": {"placementType": slot.key, "placementGroup": slot.group},
                        "relationships": {
                            relationship: {"data": {"type": resource, "id": asset_id}},
                            "appStoreVersionLocalization": {
                                "data": {"type": "appStoreVersionLocalizations", "id": localization}
                            },
                        },
                    }
                },
            )

    # MARK: Run

    def run(self, app_id: str, marketing: str, slots: list[Slot], locale: str = "en-US", live: bool = False) -> None:
        """Sync every slot. One slot's failure is recorded and the rest still run."""
        if live:
            slots = [slot for slot in slots if slot.creative]
        version_id, state = self.target_version(app_id, marketing, live)
        localization = self.localization_id(version_id, locale)
        where = "the live version" if live else f"version {marketing} ({state})"
        self.log(f"{'Syncing' if self.apply else 'Plan for'} {where}, {locale}:")

        current: list[dict] = []
        if any(slot.kind == "library" for slot in slots):
            try:
                current = self.placements(localization)
            except ASCError as error:
                self.failures.append(f"Placements: {error}")
                slots = [slot for slot in slots if slot.kind != "library"]

        for slot in slots:
            try:
                if slot.kind == "library":
                    self.sync_library(app_id, localization, slot, current, live)
                else:
                    self.sync_classic(localization, slot)
            except (ASCError, MediaError) as error:
                self.failures.append(f"{slot.label}: {error}")
                self.log(f"{slot.label}: FAILED. {error}")
