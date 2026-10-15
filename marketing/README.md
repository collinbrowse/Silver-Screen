# Marketing assets

App Store screenshots, an App Store app preview, and website clips, all made from the
real app on the simulator. One file drives them: [`titles.json`](titles.json).

```bash
python3 scripts/marketing.py screenshots   # raw PNGs, iPhone + iPad, light + dark
python3 scripts/marketing.py frame         # captioned App Store images
python3 scripts/marketing.py header        # product page header + search results art
python3 scripts/marketing.py videos        # website clips + App Store app preview
python3 scripts/marketing.py videos --reuse  # re-cut the last recording (no simulator)
```

Everything lands in `marketing/output/` (gitignored):

| Folder | What | Where it goes |
|--------|------|---------------|
| `appstore/iphone-6.3/<appearance>/` | 1206×2622, numbered in upload order | App Store Connect, iPhone 6.1"/6.3" slot (**required**) |
| `appstore/iphone/<appearance>/` | 1320×2868, numbered in upload order | App Store Connect, iPhone 6.9" slot (large iPhone; required unless you give 6.5") |
| `appstore/ipad/<appearance>/` | 2064×2752 | App Store Connect, 13" iPad (required when the app runs on iPad) |
| `appstore/header/header-<appearance>.png` | 3840×1646 (21:9), opaque PNG | Product page header (iOS 27+) |
| `appstore/header/search-<appearance>.png` | 3840×2560 (3:2), opaque PNG | Search results asset (iOS 27+) |
| `raw/` | Unframed simulator captures | Website, press kit, README |
| `video/iphone/dark/<clip>.mp4`, `.webm`, `.jpg` | Muted, looping, 720 px wide | Website |
| `video/iphone/dark/appstore-preview.mp4` | 886×1920, 30 fps, ≤ 30 s | App Store Connect app preview |
| `logs/` | Full `xcodebuild` output | Debugging a failed capture |

Needs Xcode, the gitignored `Secrets.xcconfig` (the app loads live TMDB data), and
`ffmpeg` for videos (`brew install ffmpeg`).

Apple's required sizes change; check the
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
before an upload. The 6.3" set is framed from the 6.9" captures (same shape), so it
needs no extra simulator run. iPhone Duo screenshots become required in April 2027
for apps built with the iOS 27.1 SDK.

## How it works

- Every launch uses **demo mode** (Debug builds only): a throwaway library seeded
  from `library`, opened on the `route` a shot or clip names. Your real library on
  the simulator is never touched.
- Screenshots need no taps: the script launches the app on each shot's route and
  saves the screen with `simctl`.
- The tour needs real taps, so `MarketingCaptureTests` (UI test target, run through
  the `SilverScreenMarketing` scheme) plays it while `simctl` records the screen. The
  test skips itself unless the script passes it the titles file, so a normal test
  run never records anything.
- The script sets Apple's marketing status bar (9:41, full battery and signal) and
  switches light or dark mode before each pass.
- Simulator apps cannot read `~/Documents`, so the script copies `titles.json` to
  `/tmp/ss-marketing` and copies the captures back.
- XCUITest can stall for seconds between steps while it reads the app's
  accessibility tree. Those stalls are frozen frames, so each clip has every still
  stretch trimmed to 0.8 s (`ffmpeg freezedetect`).
- Each simulator is shut down when its pass ends. On a 16 GB Mac, two booted
  simulators plus Xcode can stall app launches in paging.

## titles.json

- `shots`: App Store screenshots, in upload order. The first three carry the page.
  - `route`: where the app opens. The JSON shape of `RouterSnapshot`, for example
    `{"selectedTab": "browse", "browsePath": [{"movieDetail": {"id": 687163}}]}`.
    Award screens use `{"awardFamily": {"_0": "academy"}}` and
    `{"awardTitles": {"_0": {"family": "academy", "category": "Best Picture"}}}`.
  - `openList`: open a seeded list by name instead (list ids change every launch).
  - `settle`: seconds to wait for artwork before the capture (default 7).
  - `caption`, `subcaption`: the text `frame` puts above the screenshot.
  - `devices`: `["iphone"]` or `["ipad"]` to limit a shot. Missing means both.
  - `fresh: true` marks a shot that features current titles.
- `header`: the product page header. Following Apple's examples it has no app UI,
  only brand art (a film strip like the app icon's) and `wordmark`; `tagline` adds
  an optional short line. iPhone shows about the middle 60% under the back and share
  buttons, so the wordmark stays centered.
- `search`: the search results art: `caption` (one short phrase), an optional
  `subcaption`, and one phone showing the iPhone raw capture named in `shot`.
  Apple: no prices, URLs, awards you haven't won, or other platforms' logos. Check
  both in App Store Connect's Preview.
- `tour`: website clips, one per entry, played at a human pace and cut from one
  screen recording. Each takes `route` or `openList`, then `actions` (below);
  `hold` is how long the last frame stays.
- `library`: Watched, Watchlist, and custom lists, top to bottom, with your score and
  note per title. `hydrate` fills in everything except `id`, `kind`, `score`, `note`.

Tour actions run in order; each is one key:

| Action | Does |
|--------|------|
| `{"tap": "Save"}` | Tap the element with exactly this label (buttons win) |
| `{"tapContaining": "Oscar"}` | Tap the first element whose label contains this |
| `{"tapCell": 0}` | Tap a list cell by index |
| `{"search": "severance"}` | Type into the search field |
| `{"type": "Great.", "into": "Note"}` | Type into a labeled field |
| `{"slide": 0.9}` | Drag the first slider to 90% |
| `{"swipeUp": 2}`, `swipeDown`, `swipeLeft` | Scroll |
| `{"scrollTo": "Awards"}` | Scroll until a label is on screen |
| `{"waitFor": "Oppenheimer"}` | Wait up to 20 s for a label |
| `{"wait": 1.5}` | Pause |

## Keeping it fresh

Refresh the `fresh` shots and the website hero clip with each release, every two
or three months. App Store screenshots only change with a version submission.

The header and search art go through the Asset Library and need no new version,
so they are the place to rotate what is current: a big premiere, Oscar season
(January to March), Emmy season (September). Edit `header` or `search` and re-run
`header`.

1. `python3 scripts/marketing.py suggest` lists what is trending, now playing, and
   popular on TMDB, without unreleased titles, low-vote titles, or talk, reality,
   news, soap, and kids TV. `*` marks titles already in `titles.json`.
2. Pick titles people will recognize. A popular show nobody has heard of does less
   than an Emmy winner. Swap their ids into `library` and the `fresh` shots' routes.
3. `python3 scripts/marketing.py hydrate` fills in titles, posters, dates, and genres.
4. Re-run `screenshots`, `frame`, and `videos`.

Keep the awards shots and prestige titles (Severance, Oppenheimer, Parasite) as
they are. They don't go stale.

Product Page Optimization in App Store Connect can A/B test a "current hits" set
against an "evergreen" set without a new build.

## Website embed

The clips are muted and loop, so browsers autoplay them. Put the device frame on in
CSS rather than baking it into the video:

```html
<figure class="phone">
  <video autoplay muted loop playsinline preload="metadata" poster="rate.jpg">
    <source src="rate.webm" type="video/webm">
    <source src="rate.mp4" type="video/mp4">
  </video>
</figure>
<style>
  .phone { width: min(320px, 80vw); aspect-ratio: 1320 / 2868; margin: 0;
           padding: 10px; border-radius: 54px; background: #111;
           box-shadow: 0 0 0 2px #333, 0 30px 60px rgba(0,0,0,.35); }
  .phone video { width: 100%; height: 100%; border-radius: 44px; display: block; }
</style>
```
