# Epic: TV Watch Progress

Episode-level TV watching for Library. Movies stay binary Watched / Watchlist. TV uses In Progress plus episode completion.

| # | Story | Done |
| --- | --- | --- |
| 1 | An episode is completed or not. There is no mid-episode / “while watching” state. | [x] |
| 2 | Completing an episode puts the series on **In Progress** (automatic). The row is the series; the subtitle is `Next up: S2 · E3 · Episode name` for the episode after the highest completed one (gaps behind are ignored). If that would land past the finale while gaps remain, Next up is the first unwatched episode. | [x] |
| 3 | Completing the first episode removes the series from Watchlist. | [x] |
| 4 | Season and series completion are derived from completed episodes vs TMDB regular-season episode counts. Specials (season 0) do not count. | [x] |
| 5 | The user can mark a whole season or whole series watched. Before saving, a confirm shows how many episodes will be marked completed. | [x] |
| 6 | When every current catalog episode is completed, the series moves to Watched with a soft toast and Undo — even if another season might come later. | [x] |
| 7 | On cold launch, a background TMDB refresh compares Watched TV catalog snapshots. A new season (or more episodes) moves the series back to In Progress without blocking launch UI. | [x] |
| 8 | Watched TV rows show a season count (or “Complete”). In Progress carries the episode line. | [x] |
| 9 | TV list membership menus offer Watchlist and custom lists only — not Watched or In Progress. | [x] |
| 10 | Tapping an In Progress TV row opens that series’ season for the last watched episode and scrolls so that episode sits at the top of the viewport (next up is the row below). | [x] |
| 11 | Adding a title to Watched or In Progress without a personal score shows the in-app notice with an **Add rating** control (half-point menu). | [x] |
| 12 | Watched is never chosen from the + list menu (movies or TV). The **eye** toggles watched; + is Watchlist / custom lists only. Catalog rows use eye; horizontal carousels show an orange personal rating badge instead of +. Detail toolbars show eye and +. | [x] |
