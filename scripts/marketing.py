#!/usr/bin/env python3
"""App Store screenshots and website videos for Silver Screen.

Everything reads marketing/titles.json: the shots to take, the website tour, and
the library a capture launch starts with. See marketing/README.md.

  suggest      Shortlist current TMDB hits worth featuring (you pick; nothing is written).
  hydrate      Fill title, poster, dates, genres, and scores in titles.json from TMDB ids.
  screenshots  Run the MarketingCapture UI test per device and appearance; save raw PNGs.
  frame        Put each raw PNG on a captioned background at App Store size.
  header       Product page header (21:9) and search results art (3:2) from raw PNGs.
  videos       Record the website tour and encode MP4, WebM, and a poster frame.

No third-party packages. Tests import this module and never hit the network.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TITLES = os.path.join(ROOT, "marketing", "titles.json")
OUTPUT = os.path.join(ROOT, "marketing", "output")
# Simulator apps cannot read or write ~/Documents (macOS privacy protection), where
# a checkout often lives. The app and test runner get a copy here instead.
STAGE = "/tmp/ss-marketing"
TMDB_API = "https://api.themoviedb.org/3"

# TMDB genres that rarely make a good screenshot: kids, news, reality, soap, talk.
SKIP_TV_GENRES = {10762, 10763, 10764, 10766, 10767}
MIN_VOTES = {"movie": 200, "tv": 100}

# App Store screenshot sets. Apple requires a 6.3" iPhone set ("Dynamic Island,
# medium"), a large iPhone set (6.9" here), and a 13" iPad set when the app runs on
# iPad. The 6.3" set is framed from the 6.9" captures: same shape, so no extra run.
DEVICES = {
    "iphone": {
        "name": "SS Marketing iPhone 17 Pro Max",
        "type": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max",
        "size": (1320, 2868),
    },
    "iphone-6.3": {
        "raw_from": "iphone",
        "size": (1206, 2622),
    },
    "ipad": {
        "name": "SS Marketing iPad Pro 13",
        "type": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB",
        "size": (2064, 2752),
    },
}
CAPTURE_DEVICES = [name for name, spec in DEVICES.items() if "raw_from" not in spec]
APPEARANCES = ("light", "dark")
APP_NAME = "Silver Screen"
# Apple's creative asset sizes (iOS 27): product page header and search results.
BANNERS = {"header": (3840, 1646), "search": (3840, 2560)}


# MARK: - TMDB


def read_token(environ: dict | None = None, xcconfig_text: str | None = None) -> str:
    """TMDB read token from $TMDB_ACCESS_TOKEN, else the gitignored Secrets.xcconfig."""
    environ = os.environ if environ is None else environ
    token = environ.get("TMDB_ACCESS_TOKEN", "").strip()
    if token:
        return token
    if xcconfig_text is None:
        path = os.path.join(ROOT, "Secrets.xcconfig")
        xcconfig_text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    match = re.search(r"^\s*TMDB_ACCESS_TOKEN\s*=\s*(\S+)\s*$", xcconfig_text, re.M)
    if not match:
        sys.exit("No TMDB token: set TMDB_ACCESS_TOKEN or fill Secrets.xcconfig.")
    return match.group(1)


def make_tmdb(token: str, opener=None):
    """Returns get(path, **params) -> dict. The token rides in the header, never the URL."""
    opener = opener or urllib.request.urlopen

    def get(path: str, **params) -> dict:
        query = urllib.parse.urlencode({"language": "en-US", **params})
        request = urllib.request.Request(
            f"{TMDB_API}{path}?{query}",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        )
        with opener(request, timeout=30) as response:
            return json.load(response)

    return get


# MARK: - suggest


def candidate(raw: dict, kind: str, source: str, today: str) -> dict | None:
    """One trending or popular row, or None when it would not read well in a screenshot."""
    date = raw.get("release_date") if kind == "movie" else raw.get("first_air_date")
    if not date or date > today:
        return None
    if raw.get("adult"):
        return None
    if raw.get("vote_count", 0) < MIN_VOTES[kind]:
        return None
    if kind == "tv" and SKIP_TV_GENRES & set(raw.get("genre_ids", [])):
        return None
    if not raw.get("poster_path") or not raw.get("backdrop_path"):
        return None
    return {
        "id": raw["id"],
        "kind": kind,
        "title": raw.get("title" if kind == "movie" else "name") or "",
        "year": date[:4],
        "language": raw.get("original_language", ""),
        "voteAverage": round(raw.get("vote_average", 0), 1),
        "votes": raw.get("vote_count", 0),
        "sources": [source],
    }


def merge_candidates(rows: list[dict]) -> list[dict]:
    """Collapses repeats; a title on both trending and popular ranks above one on either."""
    merged: dict[tuple, dict] = {}
    order: list[tuple] = []
    for row in rows:
        key = (row["kind"], row["id"])
        if key in merged:
            merged[key]["sources"] = sorted(set(merged[key]["sources"]) | set(row["sources"]))
        else:
            merged[key] = dict(row)
            order.append(key)
    ranked = sorted(order, key=lambda key: (-len(merged[key]["sources"]), order.index(key)))
    return [merged[key] for key in ranked]


def suggest(get, today: str, english_only: bool, limit: int) -> list[dict]:
    rows = []
    feeds = (
        ("movie", "trending", "/trending/movie/week", {}),
        ("movie", "now playing", "/movie/now_playing", {"region": "US"}),
        ("movie", "popular", "/movie/popular", {"region": "US"}),
        ("tv", "trending", "/trending/tv/week", {}),
        ("tv", "popular", "/tv/popular", {}),
    )
    for kind, source, path, params in feeds:
        for page in (1, 2):
            for raw in get(path, page=page, **params).get("results", []):
                row = candidate(raw, kind, source, today)
                if row and (not english_only or row["language"] == "en"):
                    rows.append(row)
    merged = merge_candidates(rows)
    movies = [row for row in merged if row["kind"] == "movie"][:limit]
    shows = [row for row in merged if row["kind"] == "tv"][:limit]
    return movies + shows


def print_suggestions(rows: list[dict], featured: set[tuple]) -> None:
    for kind, heading in (("movie", "Movies"), ("tv", "TV")):
        print(f"\n{heading}")
        print(f"  {'id':>8}  {'year':4}  {'score':>5}  {'votes':>6}  title  [feeds]")
        for row in (r for r in rows if r["kind"] == kind):
            mark = "*" if (row["kind"], row["id"]) in featured else " "
            print(
                f"{mark} {row['id']:>8}  {row['year']:4}  {row['voteAverage']:>5}  {row['votes']:>6}  "
                f"{row['title']}  [{', '.join(row['sources'])}]"
            )
    print("\n* already in marketing/titles.json")


# MARK: - hydrate


def item_from_details(details: dict, kind: str, keep: dict) -> dict:
    """A library item rebuilt from TMDB details. Score and note are the user's and survive."""
    date = details.get("release_date") if kind == "movie" else details.get("first_air_date")
    item = {
        "id": details["id"],
        "kind": kind,
        "title": details.get("title" if kind == "movie" else "name") or keep.get("title", ""),
        "posterPath": details.get("poster_path"),
        "releaseDate": date or None,
        "genres": [genre["name"] for genre in details.get("genres", [])],
        "voteAverage": round(details.get("vote_average", 0), 3),
        "popularity": round(details.get("popularity", 0), 3),
    }
    for field in ("score", "note"):
        if keep.get(field) is not None:
            item[field] = keep[field]
    return item


def library_items(library: dict):
    """Every item in the seed, in file order, as mutable dicts."""
    yield from library.get("watched", [])
    yield from library.get("watchlist", [])
    for custom in library.get("lists", []):
        yield from custom.get("items", [])


def hydrate(config: dict, get) -> int:
    """Rewrites each movie or series item in place. Returns how many were refreshed."""
    count = 0
    for item in library_items(config.get("library", {})):
        if item.get("kind") not in ("movie", "tv"):
            continue
        details = get(f"/{item['kind']}/{item['id']}")
        refreshed = item_from_details(details, item["kind"], item)
        item.clear()
        item.update(refreshed)
        count += 1
    config["refreshed"] = dt.date.today().isoformat()
    return count


# MARK: - simulators


def run(command: list[str], log_path: str | None = None, env: dict | None = None) -> None:
    """Runs a command with live output; with a log path, output also goes to that file."""
    print("$", " ".join(command), flush=True)
    if log_path is None:
        subprocess.run(command, check=True, env=env)
        return
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "w", encoding="utf-8") as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
        for line in process.stdout:
            log.write(line)
            log.flush()
            if re.search(r"error:|Test Case .* (passed|failed)|\*\* .* \*\*|Skipped", line):
                print("  ", line.rstrip(), flush=True)
        if process.wait() != 0:
            sys.exit(f"Failed: {' '.join(command[:3])}… (log: {os.path.relpath(log_path, ROOT)})")


def simulator_udid(device: str) -> str:
    """The marketing simulator for an idiom, created and booted on first use."""
    spec = DEVICES[device]
    listing = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    for runtime_devices in listing["devices"].values():
        for entry in runtime_devices:
            if entry["name"] == spec["name"]:
                udid = entry["udid"]
                break
        else:
            continue
        break
    else:
        udid = subprocess.check_output(["xcrun", "simctl", "create", spec["name"], spec["type"]], text=True).strip()
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True, capture_output=True)
    return udid


def shutdown_simulator(udid: str) -> None:
    """Frees the simulator's memory. On a 16 GB Mac, two booted marketing simulators
    plus Xcode push launches into paging stalls that look like hangs."""
    simctl("shutdown", udid, check=False, attempts=1, timeout=120)


def prepare_simulator(udid: str, appearance: str) -> None:
    """Apple's marketing status bar (9:41, full signal and battery) and the requested theme."""
    subprocess.run(
        [
            "xcrun", "simctl", "status_bar", udid, "override",
            "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
            "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100",
        ],
        check=True,
    )
    subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", appearance], check=True)


def destination(udid: str) -> str:
    return f"platform=iOS Simulator,id={udid}"


def build_for_testing(udid: str) -> None:
    run(
        ["xcodebuild", "build-for-testing", "-scheme", "SilverScreenMarketing", "-destination", destination(udid),
         f"INFOPLIST_KEY_CFBundleDisplayName={APP_NAME}"],
        os.path.join(OUTPUT, "logs", "build.log"),
    )


def ui_test(udid: str, test: str, out_dir: str, log_name: str, clear_stage: bool = True) -> None:
    """Runs one MarketingCaptureTests method. TEST_RUNNER_ variables reach the test process."""
    os.makedirs(STAGE, exist_ok=True)
    staged_titles = os.path.join(STAGE, "titles.json")
    shutil.copyfile(TITLES, staged_titles)
    staged_out = os.path.join(STAGE, "out")
    if clear_stage:
        shutil.rmtree(staged_out, ignore_errors=True)
    env = dict(os.environ)
    env["TEST_RUNNER_SS_MARKETING_TITLES"] = staged_titles
    env["TEST_RUNNER_SS_MARKETING_OUT"] = staged_out
    try:
        run(
            [
                "xcodebuild", "test-without-building", "-scheme", "SilverScreenMarketing",
                "-destination", destination(udid),
                f"-only-testing:SilverScreenUITests/MarketingCaptureTests/{test}",
            ],
            os.path.join(OUTPUT, "logs", log_name),
            env=env,
        )
    finally:
        os.makedirs(out_dir, exist_ok=True)
        for name in os.listdir(staged_out) if os.path.isdir(staged_out) else []:
            if name.endswith((".png", ".json")):
                shutil.copyfile(os.path.join(staged_out, name), os.path.join(out_dir, name))


# MARK: - screenshots and frames


def raw_dir(device: str, appearance: str) -> str:
    return os.path.join(OUTPUT, "raw", device, appearance)


def install_app(udid: str) -> str:
    """Builds the Debug app for this simulator, installs it, and returns its bundle id."""
    run(
        # iPadOS shows the app's name in the status bar; use the App Store name, not "Silver Dev".
        ["xcodebuild", "build", "-scheme", "SilverScreen", "-destination", destination(udid),
         f"INFOPLIST_KEY_CFBundleDisplayName={APP_NAME}"],
        os.path.join(OUTPUT, "logs", "build-app.log"),
    )
    settings = subprocess.check_output(
        ["xcodebuild", "-showBuildSettings", "-scheme", "SilverScreen", "-destination", destination(udid)],
        text=True, stderr=subprocess.DEVNULL,
    )
    products = re.search(r"^\s*BUILT_PRODUCTS_DIR = (.+)$", settings, re.M).group(1)
    bundle_id = re.search(r"^\s*PRODUCT_BUNDLE_IDENTIFIER = (.+)$", settings, re.M).group(1)
    subprocess.run(["xcrun", "simctl", "install", udid, os.path.join(products, "SilverScreen.app")], check=True)
    return bundle_id


def simctl(*args: str, env: dict | None = None, check: bool = True, attempts: int = 3, timeout: int = 90) -> None:
    """One simctl call with a timeout. A busy CoreSimulator sometimes never answers a
    launch or terminate; a retry usually goes through where waiting does not."""
    for attempt in range(1, attempts + 1):
        try:
            result = subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True, env=env, timeout=timeout)
        except subprocess.TimeoutExpired:
            print(f"  simctl {args[0]} timed out (attempt {attempt}/{attempts})", flush=True)
            continue
        if result.returncode == 0 or not check:
            return
        print(f"  simctl {args[0]} failed: {result.stderr.strip()[:200]}", flush=True)
    if check:
        sys.exit(f"simctl {args[0]} did not succeed after {attempts} attempts.")


def demo_environment(step: dict) -> dict:
    """simctl passes SIMCTL_CHILD_ variables to the launched app without the prefix."""
    env = dict(os.environ)
    env["SIMCTL_CHILD_SS_DEMO_MODE"] = "1"
    env["SIMCTL_CHILD_SS_DEMO_SEED"] = os.path.join(STAGE, "titles.json")
    env["SIMCTL_CHILD_SS_DEMO_ROUTE"] = json.dumps(step.get("route") or {}, separators=(",", ":"))
    env["SIMCTL_CHILD_SS_DEMO_OPEN_LIST"] = step.get("openList", "")
    return env


def shots_for(config: dict, device: str, only: set[str] | None = None) -> list[dict]:
    return [
        shot for shot in config.get("shots", [])
        if device in shot.get("devices", [device]) and (not only or shot["id"] in only)
    ]


def capture_screenshots(devices: list[str], appearances: list[str], only: str | None) -> None:
    """Launches the app on each shot's route and saves the screen. No taps needed."""
    config = load_config()
    os.makedirs(STAGE, exist_ok=True)
    shutil.copyfile(TITLES, os.path.join(STAGE, "titles.json"))
    wanted = set(only.split(",")) if only else None
    for device in devices:
        udid = simulator_udid(device)
        bundle_id = install_app(udid)
        for appearance in appearances:
            prepare_simulator(udid, appearance)
            out_dir = raw_dir(device, appearance)
            os.makedirs(out_dir, exist_ok=True)
            for shot in shots_for(config, device, wanted):
                simctl("terminate", udid, bundle_id, check=False)
                simctl("launch", udid, bundle_id, env=demo_environment(shot))
                # Posters and backdrops load from TMDB; give them time to land.
                time.sleep(shot.get("settle", 7))
                path = os.path.join(out_dir, f"{shot['id']}.png")
                simctl("io", udid, "screenshot", "--type=png", path)
                print(f"  {device} {appearance} {shot['id']}", flush=True)
            simctl("terminate", udid, bundle_id, check=False)
        shutdown_simulator(udid)


def frame_jobs(config: dict, devices: list[str], appearances: list[str]) -> list[dict]:
    """One job per raw capture that has a caption. Order and numbering follow titles.json."""
    jobs = []
    for device in devices:
        width, height = DEVICES[device]["size"]
        for appearance in appearances:
            for number, shot in enumerate(shots_for(config, device), start=1):
                raw = os.path.join(raw_dir(DEVICES[device].get("raw_from", device), appearance), f"{shot['id']}.png")
                if not os.path.exists(raw) or not shot.get("caption"):
                    continue
                jobs.append({
                    "input": raw,
                    "output": os.path.join(OUTPUT, "appstore", device, appearance, f"{number:02d}-{shot['id']}.png"),
                    "caption": shot["caption"],
                    "subcaption": shot.get("subcaption", ""),
                    "width": width,
                    "height": height,
                    "device": device,
                    "appearance": appearance,
                })
    return jobs


def frame(config: dict, devices: list[str], appearances: list[str]) -> None:
    jobs = frame_jobs(config, devices, appearances)
    if not jobs:
        sys.exit("No raw screenshots yet. Run `marketing.py screenshots` first.")
    render_jobs(jobs)


def banner_jobs(config: dict, appearances: list[str]) -> list[dict]:
    """Header (brand art and wordmark, no app UI) and search art (phrase plus one
    phone, from the iPhone raw capture named in `search.shot`)."""
    header = config.get("header") or {}
    search = config.get("search") or {}
    if not header.get("wordmark") or not search.get("caption") or not search.get("shot"):
        sys.exit("titles.json needs `header.wordmark`, `search.caption`, and `search.shot`.")
    jobs = []
    for appearance in appearances:
        phone = os.path.join(raw_dir("iphone", appearance), f"{search['shot']}.png")
        if not os.path.exists(phone):
            sys.exit(f"Missing raw capture {os.path.relpath(phone, ROOT)}. Run `screenshots` first.")
        common = {"device": "iphone", "appearance": appearance}
        width, height = BANNERS["header"]
        jobs.append({
            **common,
            "kind": "header",
            "output": os.path.join(OUTPUT, "appstore", "header", f"header-{appearance}.png"),
            "caption": header["wordmark"],
            "subcaption": header.get("tagline", ""),
            "width": width,
            "height": height,
        })
        width, height = BANNERS["search"]
        jobs.append({
            **common,
            "kind": "search",
            "input": phone,
            "output": os.path.join(OUTPUT, "appstore", "header", f"search-{appearance}.png"),
            "caption": search["caption"],
            "subcaption": search.get("subcaption", ""),
            "width": width,
            "height": height,
        })
    return jobs


def render_jobs(jobs: list[dict]) -> None:
    path = os.path.join(OUTPUT, "frame-jobs.json")
    os.makedirs(OUTPUT, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(jobs, handle, indent=2)
    run(["swift", os.path.join(ROOT, "scripts", "marketing_frame.swift"), path])


# MARK: - videos


def keep_ranges(duration: float, freezes: list[tuple[float, float]], hold: float = 0.8) -> list[tuple[float, float]]:
    """Spans of a clip to keep when every still stretch is cut down to `hold` seconds.

    XCUITest can stall for many seconds reading the app's accessibility tree between
    steps. On screen that is a frozen frame, so trimming freezes removes the stall and
    keeps a short beat where the tour meant to pause.
    """
    keep, cursor = [], 0.0
    for start, end in sorted(freezes):
        cut_from = start + hold
        if end - cut_from <= 0.05 or cut_from <= cursor:
            continue
        keep.append((cursor, cut_from))
        cursor = end
    keep.append((cursor, duration))
    return [(round(a, 3), round(b, 3)) for a, b in keep if b - a > 0.05]


def parse_freezes(ffmpeg_log: str, duration: float) -> list[tuple[float, float]]:
    """freezedetect's start/end pairs; a freeze still running at the end runs to `duration`."""
    starts = [float(v) for v in re.findall(r"freeze_start: ([\d.]+)", ffmpeg_log)]
    ends = [float(v) for v in re.findall(r"freeze_end: ([\d.]+)", ffmpeg_log)]
    ends += [duration] * (len(starts) - len(ends))
    return list(zip(starts, ends))


def media_duration(path: str) -> float:
    return float(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path], text=True
    ).strip())


def ffmpeg(*args: str) -> None:
    run(["ffmpeg", "-loglevel", "error", "-y", *args])


def encode_clip(source: str, clip_id: str, out_dir: str, width: int) -> str:
    """MP4 (H.264) and WebM (VP9) at constant 30 fps, plus a poster frame, all muted."""
    base = os.path.join(out_dir, clip_id)
    cut = f"{base}.cut.mp4"
    ffmpeg("-i", source, "-vf", f"fps=30,scale={width}:-2:flags=lanczos", "-an", "-c:v", "libx264",
           "-preset", "veryfast", "-crf", "14", "-pix_fmt", "yuv420p", cut)

    duration = media_duration(cut)
    detect = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", cut, "-vf", "freezedetect=n=0.002:d=1", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    spans = keep_ranges(duration, parse_freezes(detect.stderr, duration))
    keep = "+".join(f"between(t,{a},{b})" for a, b in spans)
    ffmpeg("-i", cut, "-vf", f"select='{keep}',setpts=N/30/TB", "-an", "-c:v", "libx264", "-preset", "slow",
           "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", f"{base}.mp4")
    os.remove(cut)
    ffmpeg("-i", f"{base}.mp4", "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "34", "-row-mt", "1", "-an", f"{base}.webm")
    ffmpeg("-ss", "0.6", "-i", f"{base}.mp4", "-frames:v", "1", "-q:v", "3", f"{base}.jpg")
    return f"{base}.mp4"


def app_preview(clips: list[str], out_path: str) -> None:
    """App Store app preview for 6.9" iPhones: 886x1920, 30 fps, 15-30 s, silent stereo AAC."""
    listing = os.path.join(os.path.dirname(out_path), "concat.txt")
    with open(listing, "w", encoding="utf-8") as handle:
        handle.writelines(f"file '{clip}'\n" for clip in clips)
    ffmpeg(
        "-f", "concat", "-safe", "0", "-i", listing,
        "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
        "-t", "30", "-shortest",
        "-vf", "scale=886:1920:force_original_aspect_ratio=decrease,pad=886:1920:(ow-iw)/2:(oh-ih)/2,fps=30",
        "-c:v", "libx264", "-profile:v", "high", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", out_path,
    )
    os.remove(listing)


def tour_clips(config: dict, device: str) -> list[dict]:
    return [clip for clip in config.get("tour", []) if device in clip.get("devices", [device])]


def encode_tour(out_dir: str, device: str, width: int) -> None:
    """Encodes each recorded clip, in tour order, plus the App Store preview."""
    recorded = [
        clip for clip in tour_clips(load_config(), device)
        if os.path.exists(os.path.join(out_dir, f"{clip['id']}.mov"))
    ]
    if not recorded:
        sys.exit("No recorded clips. Run `marketing.py videos` first.")
    clips = [encode_clip(os.path.join(out_dir, f"{clip['id']}.mov"), clip["id"], out_dir, width) for clip in recorded]
    if device == "iphone":
        app_preview(clips, os.path.join(out_dir, "appstore-preview.mp4"))
    print(f"Clips in {os.path.relpath(out_dir, ROOT)}")


class ClipRecorder:
    """Answers the tour test's file handshake: records `<id>.mov` from `<id>.begin`
    to `<id>.end`, so each clip is its own file and needs no timestamp math."""

    def __init__(self, udid: str, signals: str, out_dir: str):
        self.udid, self.signals, self.out_dir = udid, signals, out_dir
        self.recorder: subprocess.Popen | None = None
        self.current: str | None = None
        self.handled: set[str] = set()

    def poll(self) -> None:
        if not os.path.isdir(self.signals):
            return
        for name in sorted(os.listdir(self.signals)):
            if name in self.handled:
                continue
            clip, _, step = name.rpartition(".")
            if step == "begin":
                self.handled.add(name)
                self.start(clip)
            elif step == "end" and clip == self.current:
                self.handled.add(name)
                self.stop()

    def start(self, clip: str) -> None:
        self.current = clip
        self.recorder = subprocess.Popen(
            ["xcrun", "simctl", "io", self.udid, "recordVideo", "--codec=h264", "--force",
             os.path.join(self.out_dir, f"{clip}.mov")],
            stderr=subprocess.PIPE, text=True,
        )
        for line in self.recorder.stderr:
            if "Recording started" in line:
                break
        open(os.path.join(self.signals, f"{clip}.go"), "w").close()
        print(f"  recording {clip}", flush=True)

    def stop(self) -> None:
        if self.recorder:
            self.recorder.send_signal(signal.SIGINT)
            self.recorder.wait(timeout=60)
        open(os.path.join(self.signals, f"{self.current}.done"), "w").close()
        self.recorder, self.current = None, None


def record_tour(device: str, appearance: str, width: int, reuse: bool = False) -> None:
    out_dir = os.path.join(OUTPUT, "video", device, appearance)
    if reuse:
        encode_tour(out_dir, device, width)
        return

    udid = simulator_udid(device)
    build_for_testing(udid)
    prepare_simulator(udid, appearance)
    os.makedirs(out_dir, exist_ok=True)
    for stale in os.listdir(out_dir):
        if stale.endswith((".mov", ".json")):
            os.remove(os.path.join(out_dir, stale))

    staged_out = os.path.join(STAGE, "out")
    shutil.rmtree(staged_out, ignore_errors=True)
    os.makedirs(staged_out)
    recorder = ClipRecorder(udid, staged_out, out_dir)
    outcome: dict = {}

    def play() -> None:
        try:
            ui_test(udid, "test_playTour", out_dir, f"tour-{device}-{appearance}.log", clear_stage=False)
        except SystemExit as error:
            outcome["failure"] = error

    test = threading.Thread(target=play)
    test.start()
    while test.is_alive():
        recorder.poll()
        time.sleep(0.1)
    if recorder.current:
        recorder.stop()
    shutdown_simulator(udid)

    encode_tour(out_dir, device, width)
    if "failure" in outcome:
        print("The tour stopped early; only the clips above were recorded.")
        raise outcome["failure"]


# MARK: - config


def load_config(path: str = TITLES) -> dict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def write_config(config: dict, path: str = TITLES) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def featured_keys(config: dict) -> set[tuple]:
    keys = {(item.get("kind"), item.get("id")) for item in library_items(config.get("library", {}))}
    for shot in config.get("shots", []) + config.get("tour", []):
        for path in (shot.get("route") or {}).values():
            if not isinstance(path, list):
                continue
            for route in path:
                if "movieDetail" in route:
                    keys.add(("movie", route["movieDetail"]["id"]))
                if "tvSeries" in route:
                    keys.add(("tv", route["tvSeries"]["id"]))
    return keys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p_suggest = sub.add_parser("suggest", help="shortlist current TMDB hits")
    p_suggest.add_argument("--limit", type=int, default=15)
    p_suggest.add_argument("--any-language", action="store_true")

    sub.add_parser("hydrate", help="refresh library metadata in titles.json from TMDB")

    for name, help_text in (
        ("screenshots", "capture raw screenshots on the marketing simulators"),
        ("frame", "caption raw screenshots at App Store sizes"),
    ):
        command = sub.add_parser(name, help=help_text)
        choices = CAPTURE_DEVICES if name == "screenshots" else list(DEVICES)
        command.add_argument("--device", choices=[*choices, "all"], default="all")
        command.add_argument("--appearance", choices=[*APPEARANCES, "all"], default="all")
        if name == "screenshots":
            command.add_argument("--only", help="comma-separated shot ids")

    p_header = sub.add_parser("header", help="product page header and search results art")
    p_header.add_argument("--appearance", choices=[*APPEARANCES, "all"], default="all")

    p_videos = sub.add_parser("videos", help="record and encode the website tour")
    p_videos.add_argument("--device", choices=CAPTURE_DEVICES, default="iphone")
    p_videos.add_argument("--appearance", choices=list(APPEARANCES), default="dark")
    p_videos.add_argument("--width", type=int, default=720, help="website clip width in pixels")
    p_videos.add_argument("--reuse", action="store_true", help="re-cut the last recording without recording again")

    args = parser.parse_args(argv)
    if args.command == "suggest":
        get = make_tmdb(read_token())
        rows = suggest(get, dt.date.today().isoformat(), not args.any_language, args.limit)
        print_suggestions(rows, featured_keys(load_config()))
    elif args.command == "hydrate":
        config = load_config()
        count = hydrate(config, make_tmdb(read_token()))
        write_config(config)
        print(f"Refreshed {count} titles in {os.path.relpath(TITLES, ROOT)}.")
    elif args.command in ("screenshots", "frame"):
        everything = CAPTURE_DEVICES if args.command == "screenshots" else list(DEVICES)
        devices = everything if args.device == "all" else [args.device]
        appearances = list(APPEARANCES) if args.appearance == "all" else [args.appearance]
        if args.command == "screenshots":
            capture_screenshots(devices, appearances, args.only)
        else:
            frame(load_config(), devices, appearances)
    elif args.command == "header":
        appearances = list(APPEARANCES) if args.appearance == "all" else [args.appearance]
        render_jobs(banner_jobs(load_config(), appearances))
    elif args.command == "videos":
        if not shutil.which("ffmpeg"):
            sys.exit("videos needs ffmpeg: brew install ffmpeg")
        record_tour(args.device, args.appearance, args.width, args.reuse)
    return 0


if __name__ == "__main__":
    sys.exit(main())
