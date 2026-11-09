#!/usr/bin/env python3
"""Marketing tooling tests. Fake TMDB responses only; nothing touches the network or a simulator."""

from __future__ import annotations

import contextlib
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import marketing  # noqa: E402

TODAY = "2026-10-14"


def movie(id_, title="Movie", date="2026-01-01", votes=500, **extra):
    row = {
        "id": id_,
        "title": title,
        "release_date": date,
        "vote_count": votes,
        "vote_average": 7.81,
        "original_language": "en",
        "poster_path": "/p.jpg",
        "backdrop_path": "/b.jpg",
        "genre_ids": [18],
    }
    row.update(extra)
    return row


def show(id_, name="Show", date="2025-01-01", votes=500, genres=(18,), **extra):
    row = movie(id_, date=date, votes=votes, **extra)
    del row["title"], row["release_date"]
    row.update({"name": name, "first_air_date": date, "genre_ids": list(genres)})
    return row


class ConnectionTests(unittest.TestCase):
    PROXY = "TMDB_BASE_URL = https:/$()/silverscreen-tmdb.example.workers.dev/3\n"

    def test_environment_token_wins_over_xcconfig(self):
        connection = marketing.read_connection({"TMDB_ACCESS_TOKEN": "env"}, "TMDB_ACCESS_TOKEN = file\n")
        self.assertEqual(connection, (marketing.TMDB_API, "env"))

    def test_reads_token_from_xcconfig_line(self):
        text = "// comment\nTMDB_ACCESS_TOKEN = eyJabc\nSENTRY_DSN =\n"
        self.assertEqual(marketing.read_connection({}, text), (marketing.TMDB_API, "eyJabc"))

    def test_token_wins_over_proxy(self):
        text = self.PROXY + "TMDB_ACCESS_TOKEN = eyJabc\n"
        self.assertEqual(marketing.read_connection({}, text), (marketing.TMDB_API, "eyJabc"))

    def test_proxy_from_xcconfig_has_no_token_and_unescapes_the_url(self):
        connection = marketing.read_connection({}, self.PROXY)
        self.assertEqual(connection, ("https://silverscreen-tmdb.example.workers.dev/3", None))

    def test_proxy_from_environment(self):
        connection = marketing.read_connection({"TMDB_BASE_URL": "https://proxy.example.dev/3/"}, "")
        self.assertEqual(connection, ("https://proxy.example.dev/3", None))

    def test_base_url_at_tmdb_itself_without_token_exits(self):
        with self.assertRaises(SystemExit):
            marketing.read_connection({}, "TMDB_BASE_URL = https:/$()/api.themoviedb.org/3\n")

    def test_nothing_set_exits(self):
        with self.assertRaises(SystemExit):
            marketing.read_connection({}, "TMDB_ACCESS_TOKEN =\n")


class MakeTMDBTests(unittest.TestCase):
    def requests_for(self, token, base):
        sent = []

        @contextlib.contextmanager
        def opener(request, timeout):
            sent.append(request)
            yield io.BytesIO(b"{}")

        marketing.make_tmdb(token, opener=opener, base=base)("/movie/1", page=2)
        return sent[0]

    def test_proxy_request_has_no_authorization_header(self):
        request = self.requests_for(None, "https://proxy.example.dev/3")
        self.assertTrue(request.full_url.startswith("https://proxy.example.dev/3/movie/1?"))
        self.assertIsNone(request.get_header("Authorization"))

    def test_requests_name_their_own_user_agent(self):
        request = self.requests_for(None, "https://proxy.example.dev/3")
        self.assertEqual(request.get_header("User-agent"), "SilverScreen-marketing/1.0")

    def test_direct_request_sends_bearer_token(self):
        request = self.requests_for("eyJabc", marketing.TMDB_API)
        self.assertEqual(request.get_header("Authorization"), "Bearer eyJabc")


class CandidateTests(unittest.TestCase):
    def test_unreleased_title_is_skipped(self):
        self.assertIsNone(marketing.candidate(movie(1, date="2026-12-25"), "movie", "trending", TODAY))

    def test_title_with_few_votes_is_skipped(self):
        self.assertIsNone(marketing.candidate(movie(1, votes=20), "movie", "trending", TODAY))

    def test_talk_and_reality_tv_is_skipped(self):
        self.assertIsNone(marketing.candidate(show(1, genres=(10767,)), "tv", "popular", TODAY))
        self.assertIsNone(marketing.candidate(show(2, genres=(10764, 18)), "tv", "popular", TODAY))

    def test_title_without_artwork_is_skipped(self):
        self.assertIsNone(marketing.candidate(movie(1, backdrop_path=None), "movie", "popular", TODAY))

    def test_released_title_keeps_display_fields(self):
        row = marketing.candidate(show(9, name="Slow Horses", date="2022-04-01"), "tv", "trending", TODAY)
        self.assertEqual(row["title"], "Slow Horses")
        self.assertEqual(row["year"], "2022")
        self.assertEqual(row["voteAverage"], 7.8)
        self.assertEqual(row["sources"], ["trending"])

    def test_merge_ranks_titles_on_more_feeds_first_and_keeps_feed_order_otherwise(self):
        rows = [
            {"kind": "movie", "id": 1, "sources": ["trending"]},
            {"kind": "movie", "id": 2, "sources": ["trending"]},
            {"kind": "movie", "id": 2, "sources": ["popular"]},
            {"kind": "movie", "id": 3, "sources": ["popular"]},
        ]
        merged = marketing.merge_candidates(rows)
        self.assertEqual([row["id"] for row in merged], [2, 1, 3])
        self.assertEqual(merged[0]["sources"], ["popular", "trending"])

    def test_suggest_filters_language_and_caps_each_kind(self):
        feeds = {
            "/trending/movie/week": [movie(1), movie(2, original_language="ko"), movie(3)],
            "/trending/tv/week": [show(10), show(11)],
        }
        get = lambda path, **params: {"results": feeds.get(path, []) if params.get("page") == 1 else []}  # noqa: E731

        rows = marketing.suggest(get, TODAY, english_only=True, limit=1)

        self.assertEqual([(row["kind"], row["id"]) for row in rows], [("movie", 1), ("tv", 10)])

    def test_suggest_without_trending_never_calls_trending_feeds(self):
        called = []

        def get(path, **params):
            called.append(path)
            return {"results": [movie(5)] if path == "/movie/now_playing" and params.get("page") == 1 else []}

        rows = marketing.suggest(get, TODAY, english_only=True, limit=5, trending=False)

        self.assertFalse(any(path.startswith("/trending/") for path in called))
        self.assertEqual([(row["kind"], row["id"]) for row in rows], [("movie", 5)])


class HydrateTests(unittest.TestCase):
    def test_item_from_details_keeps_users_score_and_note(self):
        details = {
            "id": 95396,
            "name": "Severance",
            "poster_path": "/s.jpg",
            "first_air_date": "2022-02-17",
            "genres": [{"id": 18, "name": "Drama"}, {"id": 9648, "name": "Mystery"}],
            "vote_average": 8.4123,
            "popularity": 120.5,
        }
        item = marketing.item_from_details(details, "tv", {"title": "old", "score": 9.5, "note": "Wow."})
        self.assertEqual(item["title"], "Severance")
        self.assertEqual(item["releaseDate"], "2022-02-17")
        self.assertEqual(item["genres"], ["Drama", "Mystery"])
        self.assertEqual(item["voteAverage"], 8.412)
        self.assertEqual(item["score"], 9.5)
        self.assertEqual(item["note"], "Wow.")

    def test_hydrate_rewrites_every_list_in_place_and_skips_people(self):
        config = {
            "library": {
                "watched": [{"id": 1, "kind": "movie", "title": "?"}],
                "watchlist": [{"id": 2, "kind": "tv", "title": "?"}],
                "lists": [{"name": "Faves", "items": [{"id": 3, "kind": "person", "title": "Someone"}]}],
            }
        }
        calls = []

        def get(path, **params):
            calls.append(path)
            return {"id": int(path.rsplit("/", 1)[1]), "title": "Movie", "name": "Show"}

        count = marketing.hydrate(config, get)

        self.assertEqual(count, 2)
        self.assertEqual(calls, ["/movie/1", "/tv/2"])
        self.assertEqual(config["library"]["watched"][0]["title"], "Movie")
        self.assertEqual(config["library"]["watchlist"][0]["title"], "Show")
        self.assertEqual(config["library"]["lists"][0]["items"][0]["title"], "Someone")

    def test_featured_keys_include_library_and_routed_titles(self):
        config = {
            "library": {"watched": [{"id": 1, "kind": "movie"}]},
            "shots": [{"route": {"selectedTab": "browse", "browsePath": [{"tvSeries": {"id": 5}}]}}],
            "tour": [{"route": {"searchPath": [{"movieDetail": {"id": 7}}]}}],
        }
        self.assertEqual(marketing.featured_keys(config), {("movie", 1), ("tv", 5), ("movie", 7)})


class CaptureTests(unittest.TestCase):
    CONFIG = {
        "shots": [
            {"id": "browse", "caption": "Browse"},
            {"id": "pad-only", "caption": "Big", "devices": ["ipad"]},
            {"id": "list", "caption": "Lists", "openList": "Best of 2026", "route": {"selectedTab": "library"}},
            {"id": "uncaptioned"},
        ]
    }

    def test_shots_for_honors_devices_and_only(self):
        self.assertEqual([s["id"] for s in marketing.shots_for(self.CONFIG, "iphone")], ["browse", "list", "uncaptioned"])
        self.assertEqual([s["id"] for s in marketing.shots_for(self.CONFIG, "ipad", {"pad-only"})], ["pad-only"])

    def test_demo_environment_passes_route_seed_and_list_to_the_app(self):
        env = marketing.demo_environment(self.CONFIG["shots"][2])
        self.assertEqual(env["SIMCTL_CHILD_SS_DEMO_MODE"], "1")
        self.assertEqual(env["SIMCTL_CHILD_SS_DEMO_ROUTE"], '{"selectedTab":"library"}')
        self.assertEqual(env["SIMCTL_CHILD_SS_DEMO_OPEN_LIST"], "Best of 2026")
        self.assertTrue(env["SIMCTL_CHILD_SS_DEMO_SEED"].startswith(marketing.STAGE))

    def test_frame_jobs_number_by_device_order_and_skip_missing_or_uncaptioned(self):
        with tempfile.TemporaryDirectory() as output:
            original = marketing.OUTPUT
            marketing.OUTPUT = output
            try:
                for name in ("browse", "list", "uncaptioned"):
                    path = os.path.join(marketing.raw_dir("iphone", "dark"), f"{name}.png")
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    open(path, "wb").close()
                jobs = marketing.frame_jobs(self.CONFIG, ["iphone"], ["dark"])
            finally:
                marketing.OUTPUT = original
        self.assertEqual([os.path.basename(job["output"]) for job in jobs], ["01-browse.png", "02-list.png"])
        self.assertEqual((jobs[0]["width"], jobs[0]["height"]), (1320, 2868))
        self.assertEqual(jobs[1]["caption"], "Lists")


class DeviceSetTests(unittest.TestCase):
    def test_six_point_three_set_is_framed_from_the_six_point_nine_captures_at_its_own_size(self):
        config = {"shots": [{"id": "browse", "caption": "Browse"}]}
        with tempfile.TemporaryDirectory() as output:
            original = marketing.OUTPUT
            marketing.OUTPUT = output
            try:
                raw = os.path.join(marketing.raw_dir("iphone", "dark"), "browse.png")
                os.makedirs(os.path.dirname(raw), exist_ok=True)
                open(raw, "wb").close()
                (job,) = marketing.frame_jobs(config, ["iphone-6.3"], ["dark"])
            finally:
                marketing.OUTPUT = original
        self.assertEqual(job["input"], raw)
        self.assertEqual((job["width"], job["height"]), (1206, 2622))
        self.assertIn(os.path.join("appstore", "iphone-6.3", "dark"), job["output"])

    def test_only_simulator_backed_sets_are_captured(self):
        self.assertEqual(marketing.CAPTURE_DEVICES, ["iphone", "ipad", "duo", "duo-outer"])

    def test_duo_sets_match_apples_inner_and_outer_sizes_on_one_simulator(self):
        self.assertEqual(marketing.DEVICES["duo"]["size"], (2853, 2007))
        self.assertEqual(marketing.DEVICES["duo-outer"]["size"], (1398, 2034))
        self.assertIs(marketing.simulator_spec("duo-outer"), marketing.DEVICES["duo"])
        self.assertIn("iPhone-Duo", marketing.simulator_spec("duo")["type"])

    def test_duo_captures_name_their_screen_and_others_use_the_default(self):
        self.assertEqual(marketing.screenshot_args("duo"), ["--display=primary-1"])
        self.assertEqual(marketing.screenshot_args("duo-outer"), ["--display=primary"])
        self.assertEqual(marketing.screenshot_args("iphone"), [])

    @staticmethod
    def bmp(pixels: list[tuple[int, int, int]], width: int = 10) -> bytes:
        """A 24-bit BMP with each row padded to 4 bytes, as the format requires."""
        header = bytearray(54)
        header[10:14] = (54).to_bytes(4, "little")
        header[18:22] = width.to_bytes(4, "little")
        header[22:26] = (len(pixels) // width).to_bytes(4, "little")
        header[28:30] = (24).to_bytes(2, "little")
        padding = b"\0" * (-width * 3 % 4)
        rows = [b"".join(bytes(p) for p in pixels[i:i + width]) + padding for i in range(0, len(pixels), width)]
        return bytes(header) + b"".join(rows)

    def test_lit_share_reads_an_off_screen_as_black_and_a_live_one_as_lit(self):
        off = self.bmp([(0, 0, 0)] * 999 + [(200, 200, 200)], width=37)
        live = self.bmp([(0, 0, 0), (250, 120, 30)] * 500, width=37)
        self.assertLess(marketing.lit_share(off, step=1), 0.002)
        self.assertAlmostEqual(marketing.lit_share(live, step=1), 0.5, places=2)

    def test_duo_set_with_its_screen_off_is_skipped_when_nobody_can_fold_it(self):
        original_check, original_stdin = marketing.screen_is_on, sys.stdin
        marketing.screen_is_on = lambda udid, device: False
        sys.stdin = io.StringIO()
        try:
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                self.assertFalse(marketing.ensure_screen("udid", "duo-outer"))
                self.assertFalse(marketing.ensure_screen("udid", "duo"))
                self.assertTrue(marketing.ensure_screen("udid", "iphone"))
        finally:
            marketing.screen_is_on, sys.stdin = original_check, original_stdin
        self.assertIn("fold the iPhone Duo", printed.getvalue())
        self.assertIn("unfold the iPhone Duo", printed.getvalue())

    def test_tour_is_not_offered_on_the_duo(self):
        self.assertEqual(marketing.VIDEO_DEVICES, ["iphone", "ipad"])


class BannerTests(unittest.TestCase):
    CONFIG = {
        "header": {"wordmark": "Silver Screen"},
        "search": {"caption": "Watch. Rate. Remember.", "shot": "movie-rating"},
    }

    def test_banner_jobs_make_wordmark_header_and_one_phone_search_per_appearance(self):
        with tempfile.TemporaryDirectory() as output:
            original = marketing.OUTPUT
            marketing.OUTPUT = output
            try:
                path = os.path.join(marketing.raw_dir("iphone", "dark"), "movie-rating.png")
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, "wb").close()
                header, search = marketing.banner_jobs(self.CONFIG, ["dark"])
            finally:
                marketing.OUTPUT = original
        self.assertEqual((header["kind"], header["width"], header["height"]), ("header", 3840, 1646))
        self.assertEqual(header["caption"], "Silver Screen")
        self.assertNotIn("input", header)
        self.assertEqual((search["kind"], search["width"], search["height"]), ("search", 3840, 2560))
        self.assertEqual(os.path.basename(search["input"]), "movie-rating.png")
        self.assertEqual(os.path.basename(search["output"]), "search-dark.png")

    def test_banner_jobs_without_the_search_capture_exits(self):
        with tempfile.TemporaryDirectory() as output:
            original = marketing.OUTPUT
            marketing.OUTPUT = output
            try:
                with self.assertRaises(SystemExit):
                    marketing.banner_jobs(self.CONFIG, ["dark"])
            finally:
                marketing.OUTPUT = original


class HeaderMotionTests(unittest.TestCase):
    def test_header_video_fits_apples_frame_rate_and_length_and_loops_whole_patterns(self):
        motion = marketing.HEADER_MOTION
        self.assertIn(motion["fps"], (30, 60))
        self.assertTrue(5 <= motion["seconds"] <= 30)
        self.assertIsInstance(motion["loops"], int)
        self.assertGreater(motion["loops"], 0)

    def test_motion_jobs_render_one_frame_folder_per_appearance_at_header_size(self):
        jobs = marketing.motion_jobs({"header": {"wordmark": "Silver Screen"}}, ["light", "dark"])
        self.assertEqual([job["appearance"] for job in jobs], ["light", "dark"])
        job = jobs[1]
        self.assertEqual((job["kind"], job["width"], job["height"]), ("header-motion", 3840, 1646))
        self.assertEqual(job["frames"], marketing.HEADER_MOTION["seconds"] * marketing.HEADER_MOTION["fps"])
        self.assertEqual(os.path.basename(job["output"]), "frames-dark")
        self.assertEqual(job["caption"], "Silver Screen")

    def test_motion_jobs_without_a_wordmark_exits(self):
        with self.assertRaises(SystemExit):
            marketing.motion_jobs({}, ["dark"])

    def test_header_video_is_silent_h264_read_from_numbered_frames(self):
        args = marketing.header_motion_args("/frames", "/out/header-motion-dark.mp4")
        self.assertEqual(args[args.index("-i") + 1], "/frames/frame-%04d.png")
        self.assertEqual(args[args.index("-framerate") + 1], "30")
        self.assertEqual(args[args.index("-c:v") + 1], "libx264")
        self.assertIn("-an", args)
        self.assertIn("out_color_matrix=bt709", args[args.index("-vf") + 1])
        self.assertIn("color_trc=bt709", args[args.index("-vf") + 1])
        self.assertEqual(args[-1], "/out/header-motion-dark.mp4")


class MetadataTests(unittest.TestCase):
    ATTRIBUTION = marketing.TMDB_ATTRIBUTION

    def config(self, **meta):
        base = {
            "name": "Silver Screen",
            "subtitle": "Track & rate movies and TV",
            "promotionalText": "Just saw {featured}? Rate it.",
            "description": "Keeps track of what you watch.\n\n" + self.ATTRIBUTION,
            "keywords": ["watchlist", "film"],
        }
        base.update(meta)
        return {
            "shots": [
                {"id": "browse", "fresh": True, "route": {"selectedTab": "browse"}},
                {"id": "movie", "fresh": True, "route": {"browsePath": [{"movieDetail": {"id": 1}}]}},
                {"id": "series", "fresh": True, "route": {"browsePath": [{"tvSeries": {"id": 2}}]}},
                {"id": "old", "route": {"browsePath": [{"movieDetail": {"id": 3}}]}},
            ],
            "library": {"watched": [
                {"id": 1, "kind": "movie", "title": "Project Hail Mary"},
                {"id": 2, "kind": "tv", "title": "Lanterns"},
                {"id": 3, "kind": "movie", "title": "Parasite"},
            ]},
            "metadata": base,
        }

    def test_featured_titles_come_from_fresh_shots_in_order(self):
        self.assertEqual(marketing.featured_titles(self.config()), ["Project Hail Mary", "Lanterns"])

    def test_render_fills_featured_placeholders_and_joins_keywords(self):
        fields = marketing.render_metadata(self.config(promotionalText="{featured} / {featured_all}"))
        self.assertEqual(fields["promotionalText"], "Project Hail Mary / Project Hail Mary and Lanterns")
        self.assertEqual(fields["keywords"], "watchlist,film")

    def test_valid_copy_has_no_problems(self):
        self.assertEqual(marketing.metadata_problems(marketing.render_metadata(self.config())), [])

    def test_problems_catch_limits_other_services_trademarks_and_wasted_keywords(self):
        fields = marketing.render_metadata(self.config(
            subtitle="Like Letterboxd for movies and TV, but better",
            keywords=["oscars", "movies", "film", "film"],
            description="No attribution here.",
        ))
        problems = "\n".join(marketing.metadata_problems(fields))
        self.assertIn("subtitle is 45 characters", problems)
        self.assertIn("names another service (letterboxd)", problems)
        self.assertIn("keyword 'oscars' is a trademark", problems)
        self.assertIn("keyword 'movies' is already in the name or subtitle", problems)
        self.assertIn("keywords repeat a word", problems)
        self.assertIn("missing the TMDB attribution", problems)

    def test_the_checked_in_copy_passes(self):
        fields = marketing.render_metadata(marketing.load_config())
        self.assertEqual(marketing.metadata_problems(fields), [])


class FreezeTests(unittest.TestCase):
    def test_keep_ranges_trims_each_freeze_to_the_hold(self):
        spans = marketing.keep_ranges(20.0, [(2.0, 10.0), (12.0, 12.5), (15.0, 20.0)], hold=0.8)
        self.assertEqual(spans, [(0.0, 2.8), (10.0, 15.8)])

    def test_keep_ranges_without_freezes_keeps_whole_clip(self):
        self.assertEqual(marketing.keep_ranges(6.0, []), [(0.0, 6.0)])

    def test_parse_freezes_closes_a_freeze_that_runs_to_the_end(self):
        log = (
            "[freezedetect @ 0x1] lavfi.freezedetect.freeze_start: 1.5\n"
            "[freezedetect @ 0x1] lavfi.freezedetect.freeze_end: 4.25\n"
            "[freezedetect @ 0x1] lavfi.freezedetect.freeze_start: 9\n"
        )
        self.assertEqual(marketing.parse_freezes(log, 11.0), [(1.5, 4.25), (9.0, 11.0)])


class ClipRecorderTests(unittest.TestCase):
    def test_poll_starts_on_begin_and_stops_on_end_for_the_current_clip(self):
        with tempfile.TemporaryDirectory() as signals:
            events = []
            recorder = marketing.ClipRecorder("udid", signals, signals)
            recorder.start = lambda clip: (events.append(("start", clip)), setattr(recorder, "current", clip))
            recorder.stop = lambda: (events.append(("stop", recorder.current)), setattr(recorder, "current", None))

            open(os.path.join(signals, "rate.begin"), "w").close()
            recorder.poll()
            recorder.poll()
            open(os.path.join(signals, "rate.end"), "w").close()
            recorder.poll()

        self.assertEqual(events, [("start", "rate"), ("stop", "rate")])


if __name__ == "__main__":
    unittest.main()
