#!/usr/bin/env python3
"""Tests for asc_media.py, the App Store media sync behind `release.py media`.

A fake App Store Connect records every request, so the tests check what would be
sent without touching the network.
"""

from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asc_api  # noqa: E402
import asc_media  # noqa: E402


def write_png(path: Path, size: tuple[int, int], salt: bytes = b"") -> Path:
    """A file png_size reads as a PNG of this size. The rest is filler, not pixels."""
    path.parent.mkdir(parents=True, exist_ok=True)
    head = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", *size)
    path.write_bytes(head + b"\x08\x02\x00\x00\x00" + salt)
    return path


class FakeASC:
    """In-memory App Store Connect. Routes are (method, path) → handler(query, body)."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, str, dict | None]] = []
        self.uploads: list[tuple[str, dict, bytes]] = []
        self.versions = [
            {"id": "ver-1", "attributes": {"versionString": "1.0.0", "appVersionState": "PREPARE_FOR_SUBMISSION"}}
        ]
        self.screenshot_sets: list[dict] = []
        self.screenshots: dict[str, list[dict]] = {}
        self.preview_sets: list[dict] = []
        self.library_images: list[dict] = []
        self.library_videos: list[dict] = []
        self.placements: list[dict] = []
        self.asset_states: dict[str, list[str]] = {}
        self.next_id = 0

    def new_id(self, prefix: str) -> str:
        self.next_id += 1
        return f"{prefix}-{self.next_id}"

    def client(self) -> asc_api.ASCClient:
        return asc_api.ASCClient(
            asc_api.ASCCredentials("KEY", "ISSUER", Path("/tmp/missing.p8")),
            http=self.http,
            token="test-token",
            upload=self.upload,
        )

    def upload(self, method, url, headers, body):
        self.uploads.append((url, headers, body))
        return 200

    @property
    def writes(self) -> list[tuple[str, str, dict | None]]:
        return [call for call in self.calls if call[0] != "GET"]

    def http(self, method, url, headers, body):
        parsed = urllib.parse.urlparse(url)
        path = parsed.path
        query = dict(urllib.parse.parse_qsl(parsed.query))
        payload = json.loads(body) if body else None
        self.calls.append((method, path, payload))
        return self.route(method, path, query, payload)

    def route(self, method, path, query, payload):
        parts = path.strip("/").split("/")[1:]
        if method == "GET" and parts == ["apps"]:
            return 200, {"data": [{"id": "app-1"}]}
        if method == "GET" and parts == ["apps", "app-1", "appStoreVersions"]:
            return 200, {"data": self.versions}
        if method == "POST" and parts == ["appStoreVersions"]:
            row = {"id": "ver-new", "attributes": {**payload["data"]["attributes"], "appVersionState": "PREPARE_FOR_SUBMISSION"}}
            self.versions.append(row)
            return 201, {"data": row}
        if method == "GET" and parts[-1] == "appStoreVersionLocalizations":
            return 200, {"data": [{"id": "loc-1", "attributes": {"locale": "en-US"}}]}
        if method == "GET" and parts[-1] == "appScreenshotSets":
            return 200, {"data": self.screenshot_sets}
        if method == "GET" and parts[-1] == "appPreviewSets":
            return 200, {"data": self.preview_sets}
        if method == "GET" and parts[0] == "appScreenshotSets" and parts[-1] == "appScreenshots":
            return 200, {"data": self.screenshots.get(parts[1], [])}
        if method == "POST" and parts == ["appScreenshotSets"]:
            row = {"id": self.new_id("set"), "attributes": payload["data"]["attributes"]}
            self.screenshot_sets.append(row)
            return 201, {"data": row}
        if method == "POST" and parts == ["appPreviewSets"]:
            row = {"id": self.new_id("pset"), "attributes": payload["data"]["attributes"]}
            self.preview_sets.append(row)
            return 201, {"data": row}
        if method == "POST" and parts in (["appScreenshots"], ["appPreviews"]):
            size = payload["data"]["attributes"]["fileSize"]
            return 201, {
                "data": {
                    "id": self.new_id("shot"),
                    "attributes": {
                        "uploadOperations": [
                            {
                                "method": "PUT",
                                "url": "https://upload.example/part",
                                "offset": 0,
                                "length": size,
                                "requestHeaders": [{"name": "Content-Type", "value": "image/png"}],
                            }
                        ]
                    },
                }
            }
        if method in ("PATCH", "DELETE") and parts[0] in ("appScreenshots", "appPreviews", "appAssetLibraryPlacements"):
            return (204 if method == "DELETE" else 200), {}
        if method == "GET" and parts == ["apps", "app-1", "assetLibrary"]:
            return 200, {"data": {"id": "lib-1"}}
        if method == "GET" and parts == ["appAssetLibraries", "lib-1", "images"]:
            return 200, {"data": self.library_images}
        if method == "GET" and parts == ["appAssetLibraries", "lib-1", "videos"]:
            return 200, {"data": self.library_videos}
        if method == "POST" and parts[0] in ("appAssetLibraryImages", "appAssetLibraryVideos"):
            asset_id = self.new_id("asset")
            self.asset_states[asset_id] = ["UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION"]
            return 201, {
                "data": {
                    "id": asset_id,
                    "attributes": {
                        "uploadOperations": [
                            {"method": "PUT", "url": "https://upload.example/a", "offset": 0, "length": 4},
                            {"method": "PUT", "url": "https://upload.example/b", "offset": 4,
                             "length": payload["data"]["attributes"]["fileSize"] - 4},
                        ]
                    },
                }
            }
        if method == "PATCH" and parts[0] in ("appAssetLibraryImages", "appAssetLibraryVideos"):
            return 200, {}
        if method == "GET" and parts[0] in ("appAssetLibraryImages", "appAssetLibraryVideos"):
            states = self.asset_states[parts[1]]
            state = states.pop(0) if len(states) > 1 else states[0]
            return 200, {"data": {"id": parts[1], "attributes": {"state": state}}}
        if method == "GET" and parts[-1] == "placements":
            return 200, {"data": self.placements}
        if method == "POST" and parts == ["appAssetLibraryPlacements"]:
            return 201, {"data": {"id": self.new_id("place")}}
        raise AssertionError(f"unexpected {method} {path}")


class MediaTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.output = Path(self.tmp.name) / "output"
        self.lines: list[str] = []

    def make_output(self, *, motion: bool = False, duo: bool = False) -> None:
        appstore = self.output / "appstore"
        for folder, _, size in asc_media.SCREENSHOT_SETS:
            for number in (1, 2):
                write_png(appstore / folder / "dark" / f"0{number}-shot.png", size, folder.encode() + bytes([number]))
        write_png(appstore / "header" / "header-dark.png", asc_media.HEADER_SIZE)
        write_png(appstore / "header" / "search-dark.png", asc_media.SEARCH_SIZE)
        if motion:
            (appstore / "header" / "header-motion-dark.mp4").write_bytes(b"fake mp4 bytes")
        if duo:
            write_png(appstore / "duo-outer" / "dark" / "01-shot.png", (1398, 2034))
        preview = self.output / asc_media.PREVIEW_PATH
        preview.parent.mkdir(parents=True, exist_ok=True)
        preview.write_bytes(b"preview bytes")

    def sync(self, fake: FakeASC, apply: bool) -> asc_media.MediaSync:
        return asc_media.MediaSync(fake.client(), apply=apply, log=self.lines.append, sleep=lambda _: None)


class CollectSlotsTests(MediaTestCase):
    def test_collects_every_slot_in_upload_order(self) -> None:
        self.make_output(duo=True)
        slots, notes = asc_media.collect_slots(self.output, "dark")
        self.assertEqual(
            [slot.key for slot in slots],
            [
                "APP_IPHONE_67",
                "APP_IPHONE_61",
                "APP_IPAD_PRO_3GEN_129",
                "IPHONE_67",
                "APP_SCREENSHOT",
                "PRODUCT_PAGE_HEADER_ASSET",
                "APP_STORE_SEARCH_RESULTS_ASSET",
            ],
        )
        self.assertEqual([f.path.name for f in slots[0].files], ["01-shot.png", "02-shot.png"])
        self.assertEqual(slots[4].group, "IPHONE_DUO_PROFILE")
        self.assertEqual(slots[4].category, "APP_SCREENSHOTS_AND_PREVIEWS")
        self.assertEqual(notes, [])

    def test_header_video_wins_over_the_still(self) -> None:
        self.make_output(motion=True)
        slots, _ = asc_media.collect_slots(self.output, "dark")
        header = next(slot for slot in slots if slot.key == "PRODUCT_PAGE_HEADER_ASSET")
        self.assertTrue(header.files[0].is_video)
        self.assertEqual(header.label, "Product page header video")

    def test_missing_sets_are_noted_not_failed(self) -> None:
        self.make_output()
        slots, notes = asc_media.collect_slots(self.output, "light")
        self.assertEqual([slot.key for slot in slots], ["IPHONE_67"])
        self.assertTrue(any("iphone/light" in note for note in notes))
        self.assertTrue(any("header-light" in note for note in notes))

    def test_wrong_size_stops_before_any_upload(self) -> None:
        self.make_output()
        write_png(self.output / "appstore" / "ipad" / "dark" / "03-bad.png", (1320, 2868))
        with self.assertRaises(asc_media.MediaError) as caught:
            asc_media.collect_slots(self.output, "dark")
        self.assertIn("03-bad.png is 1320×2868, expected 2064×2752", str(caught.exception))

    def test_library_name_is_content_addressed(self) -> None:
        a = write_png(Path(self.tmp.name) / "a.png", (10, 10), b"a")
        b = write_png(Path(self.tmp.name) / "b.png", (10, 10), b"a")
        c = write_png(Path(self.tmp.name) / "c.png", (10, 10), b"c")
        name = asc_media.MediaFile.read(a).library_name("header-dark")
        self.assertTrue(name.startswith("silverscreen-header-dark-") and name.endswith(".png"))
        self.assertEqual(name, asc_media.MediaFile.read(b).library_name("header-dark"))
        self.assertNotEqual(name, asc_media.MediaFile.read(c).library_name("header-dark"))


class MediaSyncTests(MediaTestCase):
    def test_plan_reads_only(self) -> None:
        self.make_output(motion=True, duo=True)
        slots, _ = asc_media.collect_slots(self.output, "dark")
        fake = FakeASC()
        sync = self.sync(fake, apply=False)
        sync.run("app-1", "1.0.0", slots)
        self.assertEqual(fake.writes, [])
        self.assertEqual(fake.uploads, [])
        self.assertEqual(sync.failures, [])
        self.assertGreater(sync.changes, 0)
        self.assertTrue(any("Screenshots APP_IPHONE_67: replace 0 with 2." in line for line in self.lines))

    def test_unchanged_screenshot_set_is_left_alone(self) -> None:
        self.make_output()
        slots, _ = asc_media.collect_slots(self.output, "dark")
        iphone = slots[0]
        fake = FakeASC()
        fake.screenshot_sets = [{"id": "set-a", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]
        fake.screenshots["set-a"] = [
            {"id": f"s{i}", "attributes": {"sourceFileChecksum": item.md5, "assetDeliveryState": {"state": "COMPLETE"}}}
            for i, item in enumerate(iphone.files)
        ]
        sync = self.sync(fake, apply=True)
        sync.sync_classic("loc-1", iphone)
        self.assertEqual(fake.writes, [])
        self.assertEqual(sync.changes, 0)

    def test_changed_screenshot_set_is_replaced_in_order(self) -> None:
        self.make_output()
        slots, _ = asc_media.collect_slots(self.output, "dark")
        iphone = slots[0]
        fake = FakeASC()
        fake.screenshot_sets = [{"id": "set-a", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]
        fake.screenshots["set-a"] = [{"id": "old-1", "attributes": {"sourceFileChecksum": "stale"}}]
        self.sync(fake, apply=True).sync_classic("loc-1", iphone)

        methods = [(method, path) for method, path, _ in fake.writes]
        self.assertEqual(methods[0], ("DELETE", "/v1/appScreenshots/old-1"))
        posts = [payload for method, path, payload in fake.writes if method == "POST"]
        self.assertEqual([p["data"]["attributes"]["fileName"] for p in posts], ["01-shot.png", "02-shot.png"])
        self.assertEqual(posts[0]["data"]["relationships"]["appScreenshotSet"]["data"]["id"], "set-a")
        commits = [payload for method, _, payload in fake.writes if method == "PATCH"]
        self.assertEqual(
            [c["data"]["attributes"] for c in commits],
            [{"uploaded": True, "sourceFileChecksum": item.md5} for item in iphone.files],
        )
        # Parts go to Apple's presigned URL with its headers, never the API token.
        self.assertEqual(len(fake.uploads), 2)
        self.assertEqual(fake.uploads[0][1], {"Content-Type": "image/png"})
        self.assertEqual(fake.uploads[0][2], iphone.files[0].path.read_bytes())

    def test_missing_screenshot_set_is_created(self) -> None:
        self.make_output()
        slots, _ = asc_media.collect_slots(self.output, "dark")
        fake = FakeASC()
        self.sync(fake, apply=True).sync_classic("loc-1", slots[1])
        created = fake.writes[0]
        self.assertEqual(created[1], "/v1/appScreenshotSets")
        self.assertEqual(created[2]["data"]["attributes"], {"screenshotDisplayType": "APP_IPHONE_61"})

    def test_new_header_is_uploaded_processed_and_placed(self) -> None:
        self.make_output(motion=True)
        slots, _ = asc_media.collect_slots(self.output, "dark")
        header = next(slot for slot in slots if slot.key == "PRODUCT_PAGE_HEADER_ASSET")
        fake = FakeASC()
        fake.placements = [
            {"id": "place-old", "attributes": {"placementType": "PRODUCT_PAGE_HEADER_ASSET", "placementGroup": "DEFAULT_PROFILE"},
             "relationships": {"image": {"data": {"id": "img-old"}}}},
            {"id": "place-search", "attributes": {"placementType": "APP_STORE_SEARCH_RESULTS_ASSET"},
             "relationships": {"image": {"data": {"id": "img-search"}}}},
        ]
        sync = self.sync(fake, apply=True)
        sync.sync_library("app-1", "loc-1", header, fake.placements, live=False)

        reserve = next(p for m, path, p in fake.writes if path == "/v1/appAssetLibraryVideos")
        self.assertEqual(reserve["data"]["attributes"]["category"], "CREATIVE_ASSETS")
        self.assertEqual(reserve["data"]["attributes"]["fileName"], header.files[0].library_name("header-dark"))
        data = header.files[0].path.read_bytes()
        self.assertEqual(b"".join(body for _, _, body in fake.uploads), data)
        # Polled until processing finished, before placing.
        polls = [path for method, path, _ in fake.calls if method == "GET" and path.startswith("/v1/appAssetLibraryVideos/")]
        self.assertEqual(len(polls), 2)
        self.assertIn(("DELETE", "/v1/appAssetLibraryPlacements/place-old", None), fake.writes)
        self.assertNotIn(("DELETE", "/v1/appAssetLibraryPlacements/place-search", None), fake.writes)
        placed = [p for m, path, p in fake.writes if path == "/v1/appAssetLibraryPlacements"][0]["data"]
        self.assertEqual(placed["attributes"], {"placementType": "PRODUCT_PAGE_HEADER_ASSET", "placementGroup": "DEFAULT_PROFILE"})
        self.assertEqual(placed["relationships"]["video"]["data"]["type"], "appAssetLibraryVideos")
        self.assertEqual(placed["relationships"]["appStoreVersionLocalization"]["data"]["id"], "loc-1")

    def test_placed_asset_already_in_library_is_unchanged(self) -> None:
        self.make_output()
        slots, _ = asc_media.collect_slots(self.output, "dark")
        search = next(slot for slot in slots if slot.key == "APP_STORE_SEARCH_RESULTS_ASSET")
        fake = FakeASC()
        fake.library_images = [
            {"id": "img-1", "attributes": {"fileName": search.files[0].library_name("search-dark"), "state": "APPROVED"}}
        ]
        fake.placements = [
            {"id": "p", "attributes": {"placementType": "APP_STORE_SEARCH_RESULTS_ASSET", "placementGroup": "DEFAULT_PROFILE"},
             "relationships": {"image": {"data": {"id": "img-1"}}}}
        ]
        sync = self.sync(fake, apply=True)
        sync.sync_library("app-1", "loc-1", search, fake.placements, live=False)
        self.assertEqual(fake.writes, [])
        self.assertEqual(sync.changes, 0)

    def test_library_asset_still_processing_is_awaited_before_placing(self) -> None:
        self.make_output()
        slots, _ = asc_media.collect_slots(self.output, "dark")
        search = next(slot for slot in slots if slot.key == "APP_STORE_SEARCH_RESULTS_ASSET")
        fake = FakeASC()
        fake.library_images = [
            {"id": "img-1", "attributes": {"fileName": search.files[0].library_name("search-dark"), "state": "UPLOAD_COMPLETE"}}
        ]
        fake.asset_states["img-1"] = ["UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION"]
        sync = self.sync(fake, apply=True)
        sync.sync_library("app-1", "loc-1", search, [], live=False)
        polls = [path for method, path, _ in fake.calls if method == "GET" and path == "/v1/appAssetLibraryImages/img-1"]
        self.assertEqual(len(polls), 2)
        self.assertFalse(any(path == "/v1/appAssetLibraryImages" for _, path, _ in fake.writes))
        placed = [p for m, path, p in fake.writes if path == "/v1/appAssetLibraryPlacements"][0]["data"]
        self.assertEqual(placed["relationships"]["image"]["data"]["id"], "img-1")

    def test_approved_duplicate_wins_over_later_copy(self) -> None:
        self.make_output()
        slots, _ = asc_media.collect_slots(self.output, "dark")
        search = next(slot for slot in slots if slot.key == "APP_STORE_SEARCH_RESULTS_ASSET")
        name = search.files[0].library_name("search-dark")
        fake = FakeASC()
        fake.library_images = [
            {"id": "img-ok", "attributes": {"fileName": name, "state": "APPROVED"}},
            {"id": "img-dup", "attributes": {"fileName": name, "state": "PREPARE_FOR_SUBMISSION"}},
        ]
        assets = self.sync(fake, apply=False).library_assets("app-1")
        self.assertEqual(assets[name][1], "img-ok")

    def test_live_version_only_takes_approved_art(self) -> None:
        self.make_output()
        slots, _ = asc_media.collect_slots(self.output, "dark")
        fake = FakeASC()
        fake.versions = [{"id": "ver-live", "attributes": {"versionString": "1.0.0", "appStoreState": "READY_FOR_SALE"}}]
        sync = self.sync(fake, apply=True)
        sync.run("app-1", "1.0.0", slots, live=True)
        self.assertFalse(any(path == "/v1/appAssetLibraryPlacements" for _, path, _ in fake.writes))
        self.assertFalse(any("appScreenshot" in path for _, path, _ in fake.calls))
        self.assertTrue(any("until App Review approves" in line for line in self.lines))

    def test_missing_version_is_created(self) -> None:
        fake = FakeASC()
        fake.versions = [{"id": "ver-0", "attributes": {"versionString": "0.9.0", "appStoreState": "READY_FOR_SALE"}}]
        version, _ = self.sync(fake, apply=True).target_version("app-1", "1.0.0", live=False)
        self.assertEqual(version, "ver-new")
        self.assertEqual(fake.writes[0][2]["data"]["attributes"], {"platform": "IOS", "versionString": "1.0.0"})

    def test_plan_does_not_create_a_version(self) -> None:
        fake = FakeASC()
        fake.versions = []
        version, _ = self.sync(fake, apply=False).target_version("app-1", "1.0.0", live=False)
        self.assertIsNone(version)
        self.assertEqual(fake.writes, [])

    def test_other_version_in_preparation_is_an_error(self) -> None:
        fake = FakeASC()
        fake.versions = [{"id": "v", "attributes": {"versionString": "1.1.0", "appVersionState": "PREPARE_FOR_SUBMISSION"}}]
        with self.assertRaises(asc_media.MediaError) as caught:
            self.sync(fake, apply=True).target_version("app-1", "1.2.0", live=False)
        self.assertIn("1.1.0", str(caught.exception))
        self.assertEqual(fake.writes, [])

    def test_version_in_review_is_locked(self) -> None:
        fake = FakeASC()
        fake.versions = [{"id": "v", "attributes": {"versionString": "1.0.0", "appVersionState": "WAITING_FOR_REVIEW"}}]
        with self.assertRaises(asc_media.MediaError):
            self.sync(fake, apply=True).target_version("app-1", "1.0.0", live=False)

    def test_failed_processing_is_reported_and_other_slots_continue(self) -> None:
        self.make_output()
        slots, _ = asc_media.collect_slots(self.output, "dark")
        fake = FakeASC()
        original = fake.route

        def route(method, path, query, payload):
            status, body = original(method, path, query, payload)
            if method == "POST" and path == "/v1/appAssetLibraryImages":
                fake.asset_states[body["data"]["id"]] = ["FAILED"]
            return status, body

        fake.route = route
        sync = self.sync(fake, apply=True)
        sync.run("app-1", "1.0.0", slots)
        self.assertEqual(len(sync.failures), 2)
        self.assertTrue(all("could not process" in failure for failure in sync.failures))
        self.assertTrue(any(path == "/v1/appPreviews" for _, path, _ in fake.writes))


class ClientPagingTests(unittest.TestCase):
    def test_get_all_follows_next_links(self) -> None:
        urls: list[str] = []

        def http(method, url, headers, body):
            urls.append(url)
            if "cursor" in url:
                return 200, {"data": [{"id": "2"}], "included": [{"id": "i2"}]}
            return 200, {
                "data": [{"id": "1"}],
                "included": [{"id": "i1"}],
                "links": {"next": "https://api.appstoreconnect.apple.com/v1/x?cursor=abc"},
            }

        client = asc_api.ASCClient(asc_api.ASCCredentials("K", "I", Path("/tmp/x.p8")), http=http, token="t")
        rows, included = client.get_all("/v1/x", {"limit": "1"})
        self.assertEqual([row["id"] for row in rows], ["1", "2"])
        self.assertEqual([row["id"] for row in included], ["i1", "i2"])
        self.assertEqual(urls[1], "https://api.appstoreconnect.apple.com/v1/x?cursor=abc")

    def test_upload_part_failure_is_an_asc_error(self) -> None:
        client = asc_api.ASCClient(
            asc_api.ASCCredentials("K", "I", Path("/tmp/x.p8")),
            http=lambda *a: (200, {}),
            token="t",
            upload=lambda method, url, headers, body: 403,
        )
        with self.assertRaises(asc_api.ASCError):
            client.upload_parts([{"method": "PUT", "url": "https://u", "offset": 0, "length": 1}], b"x")


if __name__ == "__main__":
    unittest.main()
