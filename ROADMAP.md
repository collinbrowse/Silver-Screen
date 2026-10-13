# Persistence & sync roadmap

Path from today’s on-device library to accounts and a social product. Design detail
for the storage model is in [`PERSISTENCE.md`](PERSISTENCE.md).

## Dependency order

```
Local SQLite → Sync scaffold → Auth + accounts → Sync API → Social
```

Accounts and authentication are **one gate**. No user library data is stored on a
server until there is an authenticated account. Discovery (TMDB, awards catalog)
can keep using the network without that gate.

| Phase | Ships | User data on server? |
|-------|--------|----------------------|
| **0 — Docs** | This roadmap, `PERSISTENCE.md` | No |
| **1 — Local SQLite** | One `library.sqlite` (WAL); JSON import; domain-scoped replace; repos on SQLite | No |
| **2 — Sync scaffold** | `sync_outbox` on mutations; cursors; `SyncEngine` no-op drain | No |
| **3 — Auth + accounts** | Sign-in, Keychain session, `account_id` | Account records only |
| **4 — Sync API** | Authenticated push/pull; sign-in merge / sign-out policy | Yes — library after session |
| **5 — Social** | Follows / likes / comments as server resources + thin local caches | Yes — not full-document blobs |

## Phase notes

### 1 — Local SQLite (current)

Replace `lists.json`, `annotations.json`, and `tv-progress.json` full-file rewrites
with domain-scoped SQL replace (a lists save does not rewrite annotations or TV
progress). View models stay on repository APIs. Sync metadata columns and empty
outbox/cursor tables exist but are unused. Per-row mutations come later.

### 2 — Sync scaffold

Every local mutation also appends an outbox row. No network. Proves the write path
is sync-shaped before a backend exists.

### 3 — Auth + accounts

Identity first. Sign in with Apple (or equivalent) + Keychain. Do not accept
library uploads without a session.

### 4 — Sync API

Idempotent push of the outbox; cursor pull; conflict policy (server-arbitered LWW
on revision). Explicit wipe-or-keep on sign-out.

### 5 — Social

Server-owned graphs and feeds. Device caches what the UI needs; do not extend the
local library document into a social dump.

## Non-goals

- Third-party ORMs (GRDB, Realm, …)
- CloudKit as the social / account backend
- Awards catalog inside `library.sqlite`
- CRDT list ordering until a product case requires it
- Server-only personal library (no local store)
