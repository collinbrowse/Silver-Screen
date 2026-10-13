# Persistence scalability

Staff-level redesign of on-device user data. Product rules stay in the repositories;
this document defines the **storage model** under them.

Roadmap (phases through social): [`ROADMAP.md`](ROADMAP.md).  
Related: [`NOTES.md`](NOTES.md), [`.cursor/rules/architecture.mdc`](.cursor/rules/architecture.mdc),
[`.cursor/rules/data-layer.mdc`](.cursor/rules/data-layer.mdc).

---

## Verdict

Full-snapshot JSON (`lists.json`, `annotations.json`, `tv-progress.json`) is wrong as
the foundation for large libraries, multi-device accounts, and a future social backend.

**Replace it with one local SQLite database (WAL), a domain-scoped `LibraryStore`
(replace-all per lists / annotations / TV, not per row), a one-shot JSON importer,
and sync-ready row metadata.** Keep repositories as the only API screens see. No
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

Lists, annotations, and TV watch share a connection so cross-domain work can be one
transaction later. Navigation stays in `UserDefaults`. Awards stay a separate cache.

Production DI builds `SQLiteLibraryStore`, runs `bootstrap()`, and exposes narrow
`ListsStore` / `AnnotationsStore` / `TVWatchStore` adapters so repositories and tests
keep familiar seams. Each adapter save is a **domain-scoped replace**: it rewrites
that domain’s tables and leaves the others alone. Row-level mutations are a later
phase; repositories still persist a snapshot through the adapter.

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
| `revision` | Monotonic per row on local write |
| `updated_at` | Display + coarse conflict hints |
| `deleted_at` | Tombstone |

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
