# Persistence scalability

Staff-level redesign of on-device user data. Product rules stay in the repositories;
this document defines the **storage model** under them.

Roadmap (phases through social): [`ROADMAP.md`](ROADMAP.md).  
Related: [`NOTES.md`](NOTES.md), [`.claude/rules/architecture.md`](.claude/rules/architecture.md),
[`.claude/rules/data-layer.md`](.claude/rules/data-layer.md).

---

## Verdict

Full-snapshot JSON (`lists.json`, `annotations.json`, `tv-progress.json`) is wrong as
the foundation for large libraries, multi-device accounts, and a future social backend.

**Replace it with one local SQLite database (WAL), a domain-scoped `LibraryStore`
(one snapshot per lists / annotations / TV, diffed against stored rows), a one-shot
JSON importer, and sync-ready row metadata.** Keep repositories as the only API screens see. No
CloudKit, Core Data, SwiftData, or third-party ORM.

---

## What existed (JSON era)

| Surface | File | Pattern |
|--------|------|---------|
| Lists | `lists.json` | Load entire `LibrarySnapshot`, rewrite file |
| Annotations | `annotations.json` | Load entire `[MediaAnnotation]`, rewrite file |
| TV progress | `tv-progress.json` | Load entire `[TVSeriesWatchState]`, rewrite file |
| Navigation | `UserDefaults` | Encode on background only |
| Awards catalog | Bundle + cached JSON | Read-only shared catalog; not user data |

Pain points: O(library) I/O per toggle, denormalized `ListEntry` copies, unused
`version` fields, quarantine-to-empty, no sync primitives, launch amplification in
`WatchedRatings.sync`, domain types as on-disk wire format.

---

## Target architecture

```
View → ViewModel → Repository → LibraryStore → SQLite
                              ↘ (later) SyncEngine → Account API
```

One file: `Application Support/SilverScreen/library.sqlite`.

Lists, annotations, TV watch, and the diary share a connection so cross-domain work can be one
transaction later. Navigation stays in `UserDefaults`. Awards stay a separate cache.

Production DI builds `SQLiteLibraryStore`, runs `bootstrap()`, and exposes narrow
`ListsStore` / `AnnotationsStore` / `TVWatchStore` / `DiaryStore` adapters so repositories and tests
keep familiar seams. Each adapter save is a **domain-scoped diff**: repositories still
hand over a whole-domain snapshot, and the store compares it with that domain’s rows
in one transaction, leaving the other domains alone. Row-level mutations are a later
phase.

### Diffed writes

`writeLists`, `writeAnnotations`, `writeTVWatch`, and `writeDiary` match each snapshot row to its
stored row by primary key (deterministic ids from `LibraryStableID` for memberships
and annotations) and upsert it with `INSERT … ON CONFLICT … DO UPDATE … WHERE`:

| Snapshot vs stored row | Effect |
|------------------------|--------|
| New key | Insert with `revision = 1`, `updated_at` = `created_at` = now |
| Same content | Untouched: `revision` and `updated_at` keep their values |
| Changed content | Update, `revision + 1`, `updated_at` = now; `created_at` kept |
| Key matches a tombstone | Revive: clear `deleted_at`, `revision + 1`, fresh `created_at` |
| Stored live row missing from snapshot | Tombstone: `deleted_at` = `updated_at` = now, `revision + 1` |

Rows are never hard-deleted, so `UNIQUE` keys never collide on re-add and a removal
can sync later. Every read filters `deleted_at IS NULL`. `media_item` rows no longer
referenced by any entry are tombstoned with the lists domain. The JSON encoder sorts
keys so an unchanged `catalog_snapshot_json` or `genre_names_json` compares equal.

---

## Schema (v1)

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE media_item (
  item_key TEXT PRIMARY KEY,
  tmdb_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  image_path TEXT,
  release_date TEXT,
  genre_names_json TEXT NOT NULL DEFAULT '[]',
  vote_average REAL NOT NULL DEFAULT 0,
  popularity REAL NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT
);

CREATE TABLE library_list (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  segment TEXT NOT NULL,
  system_kind TEXT,
  sort TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT
);

CREATE TABLE list_membership (
  id TEXT PRIMARY KEY,
  list_id TEXT NOT NULL REFERENCES library_list(id),
  item_key TEXT NOT NULL REFERENCES media_item(item_key),
  added_at TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT,
  UNIQUE(list_id, item_key)
);

CREATE TABLE annotation (
  id TEXT PRIMARY KEY,
  item_key TEXT NOT NULL,
  kind TEXT NOT NULL,
  subject_id INTEGER NOT NULL,
  season_number INTEGER NOT NULL DEFAULT 0,
  episode_number INTEGER NOT NULL DEFAULT 0,
  score REAL,
  note TEXT,
  watched_at TEXT,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT,
  UNIQUE(kind, subject_id, season_number, episode_number)
);

CREATE TABLE tv_series_watch (
  series_id INTEGER PRIMARY KEY,
  next_up_season INTEGER,
  next_up_episode INTEGER,
  next_up_title TEXT,
  catalog_snapshot_json TEXT,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT
);

CREATE TABLE tv_episode_completed (
  series_id INTEGER NOT NULL REFERENCES tv_series_watch(series_id),
  season_number INTEGER NOT NULL,
  episode_number INTEGER NOT NULL,
  PRIMARY KEY (series_id, season_number, episode_number)
);

CREATE TABLE sync_outbox (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT
);

CREATE TABLE sync_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

`sync_outbox` is not written until roadmap Phase 2. Row `revision` / `deleted_at` exist
from day one so Phase 4 sync does not require another on-disk format break.

Schema v2 adds `media_item(kind, popularity)` so N→N+1 is an explicit, tested
migration. Later versions keep that loop in `SQLiteLibraryStore.migrateSchema()`.

Schema v3 makes history survive the diffed writes:

| Table | Added | Backfill |
|-------|-------|----------|
| `library_list` | `created_at` | Earliest `added_at` among its memberships, else `updated_at` |
| `annotation` | `created_at` | `watched_at`, else the title’s earliest list `added_at`, else `updated_at` |
| `tv_episode_completed` | `completed_at`, `updated_at`, `revision`, `deleted_at` | The episode annotation’s `watched_at`, else the series’ `updated_at` |

Each backfill falls back to the migration time if nothing is stored. Under v2 every
save reset `updated_at`, so it is only an upper bound on the real date; v3 keeps the
best evidence available at upgrade and every later write preserves it.
Unmarking an episode now tombstones its `tv_episode_completed` row instead of
deleting it. The new columns are nullable because `ALTER TABLE ADD COLUMN` cannot add
`NOT NULL` without a constant default; the store always writes them.

Schema v4 adds the diary: one row per logged watch, many per title.

```sql
CREATE TABLE diary_entry (
  id TEXT PRIMARY KEY,               -- UUID; deterministic for backfilled and imported rows
  kind TEXT NOT NULL,                -- 'movie' or 'tv'
  tmdb_id INTEGER NOT NULL,
  title TEXT NOT NULL,               -- snapshot when logged
  release_year INTEGER,              -- snapshot when logged
  image_path TEXT,
  watched_on TEXT NOT NULL,          -- 'yyyy-MM-dd' calendar day, no time or timezone
  score REAL,                        -- 0.5–10 half points, for this watch only
  review TEXT,                       -- for this watch only
  is_rewatch INTEGER NOT NULL DEFAULT 0,
  tags_json TEXT NOT NULL DEFAULT '[]',
  logged_at TEXT NOT NULL,           -- when the entry was logged (imports keep the original)
  created_at TEXT NOT NULL,          -- when the row first existed on this device
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  deleted_at TEXT
);
CREATE INDEX diary_entry_watched_on ON diary_entry(watched_on);
CREATE INDEX diary_entry_subject ON diary_entry(kind, tmdb_id);
```

Schema v5 lets an entry be about one TV episode:

```sql
ALTER TABLE diary_entry ADD COLUMN season_number INTEGER;  -- NULL for a movie or whole series
ALTER TABLE diary_entry ADD COLUMN episode_number INTEGER; -- NULL for a movie or whole series
CREATE INDEX diary_entry_episode ON diary_entry(kind, tmdb_id, season_number, episode_number);
```

Schema v6 lets a watch have no known day, and reconciles the data so the rules below hold:

```sql
ALTER TABLE diary_entry ADD COLUMN date_known INTEGER NOT NULL DEFAULT 1; -- 0 = "Don't remember"
```

`watched_on` stays `NOT NULL` as a sort anchor because SQLite cannot relax that without
rebuilding the table. A row with `date_known = 0` is shown as undated, sorts as the oldest,
stays off the diary timeline, and appears under "Earlier" in Watch History.

The v6 data pass runs in Swift in the migration's transaction
(`SQLiteLibraryStore+WatchReconcile.swift`), and again after the legacy JSON import, so it is
idempotent. In order, it: gives each completed episode an entry dated `completed_at`; retires
whole-series entries of shows with episodes, moving their score and review into the empty
parts of the show's verdict; gives an undated watch to each movie on Watched or with a score
but no entry; puts every movie with an entry on Watched and off the Watchlist; and moves each
movie and episode annotation's score and note onto its newest watch. The saved score wins
over that watch's own, so every page shows the rating it showed before. A note already in the
review is not repeated. A note on an unwatched title stays on its annotation.

Decisions:

- **A title is watched exactly when it has a watch.** `diary_entry` is the one store of
  watches. Movies and episodes are watched; a season or show counts when all its episodes do.
  `WatchRepository` and `TVWatchRepository` are the only writers, so the diary, Watched, In
  Progress, and ratings change together, and each rolls back its first write if a later one
  fails. Removing a title's last watch takes it off Watched, or out of TV progress.
- **`tv_episode_completed` is a progress cache.** It stays because next up, In Progress, and
  the catalog snapshot read it, and it is written beside the entries. A TMDB catalog prune
  only changes progress: removals are always explicit, so a prune never deletes a watch.
- **The eye logs and removes; Log a Rewatch logs again.** The grey eye inserts a `diary_entry`
  dated today, and the orange eye deletes every watch of the title, asking first when there
  is more than one. Undo revives the same ids. Onboarding's "seen it" picks are undated.
- **A first watch adopts what was saved before it.** Any score and note on the title's
  annotation move onto the watch (`AnnotationsRepository.adopt`), and Undo puts them back.
- **The diary groups plain watches.** First watches of one show's episodes on one day, with
  no rating or review, share one row ("S2 · E3–E5") that opens the show. A rated, reviewed, or
  rewatched episode gets its own row with its own edit and delete. A season rewatch is one
  entry per episode with a shared `logged_at`, which is how the diary shows it as one row.
- **The title's rating is its newest rated watch.** `diary_entry.score` and `review` describe
  that viewing, and `annotation.score` is a cached copy for list rows
  (`WatchRepository.ratedWatch`, `AnnotationsRepository.syncRating`). Every save, delete, and
  undo repoints it, so an unrated rewatch keeps your rating and deleting a watch falls back to
  the next rated one. Rating never records a watch: an unwatched title shows only its TMDB score.
- **Seasons and shows get a verdict, not a watch.** Their score and review stay on
  `annotation` (`kind = tvSeason` or `tvSeries`, the review in `note`) and stay out of the diary.
- **No tags.** The app has no tags: nothing reads or writes `tags_json`, and the log
  sheet has no field for them. The column stays at its default `'[]'` because schema v4
  already created it on development installs; a later schema version can drop it.
- **Rewatches are worked out, not switched.** The diary badges every watch of a title
  after its earliest entry as a rewatch. `is_rewatch` is only set by a Letterboxd import
  (or kept through an edit), which covers a first log of something seen before the app;
  a new log stores `0`. Deleting the first watch makes the next one the first. An undated
  watch counts as the first.
- **`watched_on` is a calendar day.** It is computed on the device calendar when logged,
  so a late-night watch keeps its day when the phone changes timezone.

Backfill (in Swift, inside the v4 migration transaction, because ids come from
`LibraryStableID`): every live movie or series on the Watched system list gets one entry.

| Column | Backfilled from |
|--------|-----------------|
| `id` | `LibraryStableID.uuid("diary:backfill:<item_key>")`, so two devices agree and a re-run never duplicates |
| `watched_on`, `logged_at`, `created_at`, `updated_at` | Earliest of the title's `annotation.watched_at` and its Watched `added_at` |
| `score`, `review` | The title's current `annotation.score` and `note` (series use the series annotation) |
| `title`, `release_year`, `image_path` | `media_item` |
| `is_rewatch` | `0` (`tags_json` is left at its default) |

Tombstoned Watched rows and Watchlist-only titles get no entry. The legacy JSON import
runs the same backfill after it writes lists, because v4 ran before those lists existed;
`ON CONFLICT(id) DO NOTHING` keeps it from reviving an entry someone deleted.

### Letterboxd mapping

Letterboxd exports `diary.csv` (Date, Name, Year, Letterboxd URI, Rating, Rewatch, Tags,
Watched Date) and `reviews.csv` (the same plus Review). Each row maps to one entry:

| Letterboxd | `diary_entry` | Notes |
|------------|---------------|-------|
| `Date` | `logged_at` | Day the entry was logged; store as that day's midnight UTC |
| `Name` | `title` | Also the TMDB search query |
| `Year` | `release_year` | Narrows the TMDB match |
| `Letterboxd URI` | `id` | `LibraryStableID.uuid("diary:letterboxd:<uri>")`; re-importing the same file upserts the same rows |
| `Rating` | `score` | `LetterboxdRating.score(fromStars:)`: stars × 2, exact. Empty means unrated |
| `Rewatch` | `is_rewatch` | `Yes` → 1, empty → 0 |
| `Tags` | — | Not imported; the app has no tags |
| `Watched Date` | `watched_on` | Already `yyyy-MM-dd`; `DiaryDay(iso:)` |
| `Review` (reviews.csv) | `review` | Join to the diary row on `Letterboxd URI` |
| — | `kind`, `tmdb_id`, `image_path` | `movie`, then the TMDB match for Name + Year |

Export goes the other way with `LetterboxdRating.stars(fromScore:)`, which rounds odd
half points to the nearest half star (7.5 → 4★). An importer should skip ids that are
tombstoned, so a deleted entry stays deleted, and should put each imported film on
Watched (`ListsRepository.addToWatched`) the way logging does.

---

## JSON migration

On `bootstrap()`:

1. Open/create DB and apply migrations.
2. If `sync_state['json_import']` is unset and any legacy JSON file exists:
   - If every domain already has SQL rows → prefer SQLite; rename JSON to `*.imported`.
   - Else load all three JSON files and, in **one transaction**, write only the
     empty domains, then set the stamp. Rename JSON to `*.imported` after commit.
     A crash cannot commit lists without annotations/TV/stamp; leftover JSON for
     an empty domain is still imported on the next launch.
3. Never wipe the SQL database because one row failed to decode.

---

## Sync-ready fields (unused until accounts)

| Field | Role |
|-------|------|
| Stable UUID / deterministic id | Device and server agree on identity |
| `revision` | Bumped only when a row’s content changes, is tombstoned, or is revived |
| `updated_at` | Time of the row’s last real change; display + coarse conflict hints |
| `created_at` / `completed_at` | When the rating, list, episode, or diary entry first existed (v3, v4) |
| `deleted_at` | Tombstone; set instead of deleting the row |

Anonymous installs: no `account_id`, data stays local. Sign-in (Phase 3–4) attaches an
account and drains the outbox.

---

## Alternatives rejected

| Option | Why not |
|--------|---------|
| More JSON shards | Still document replace; no indexes/merge |
| SwiftData / Core Data + CloudKit | Weak seam control; CloudKit ≠ social backend |
| GRDB / Realm | Third-party ban |
| Server-only | Personal library must not share fate with TMDB/API uptime |

---

## Success criteria (Phase 1)

- A lists write does not rewrite annotation or TV-progress tables (and vice versa).
- Schema N→N+1 is an explicit migration with a test.
- Fresh install and JSON→SQLite upgrade both work.
- No third-party persistence dependency.
- View models unchanged at the product API.
