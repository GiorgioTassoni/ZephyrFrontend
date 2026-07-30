# Changelog

Concrete code changes shipped in this iteration, in order. Each entry lists what changed, why, and how to verify. Details on any one change are in the section, not buried in a wall of prose.

---

## 1. Schema cleanup (pure `CREATE`, no `ALTER` / `DO`)

**Before**: `schema.sql` mixed 11 `CREATE TABLE IF NOT EXISTS` + 12 `CREATE INDEX IF NOT EXISTS` with 5 `ALTER TABLE … ADD COLUMN IF NOT EXISTS …` blocks and 4 `DO $$ … $$` blocks (renames + constraint validity). ~140 lines, hard to read top-to-bottom.

**After**: same 11 tables + 13 indexes, **zero** `ALTER TABLE`, **zero** `DO $$`, in pure dependency order (parents before children).

| File | Lines (was → is) |
|---|---|
| `schema.sql` | ~140 → ~85 |

**Why**: dev DB only (no production deploy). The `CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS` already guarantees idempotency on FastAPI restart — no need for runtime ALTER guards.

**FK preservation**: the constraint name `fk_tracks_album_id` is preserved via inline `CONSTRAINT fk_tracks_album_id REFERENCES …` syntax, so `BACKFILL/13_verify.sql`'s `pg_constraint.conname = 'fk_tracks_album_id'` lookup still matches.

**Verify**:
```bash
grep -E '\bALTER\s+TABLE\b|\bDO\s+\$\$' schema.sql    # expect: nothing
grep -cE '\bCREATE\s+TABLE\b' schema.sql              # expect: 11
grep -cE '\bCREATE\s+(UNIQUE\s+)?INDEX\b' schema.sql   # expect: 13
```

---

## 2. `albums.browse_id → albums.id` rename

One conceptual rename applied in 14 files: schema column, all readers, all writers, all callers, all URL paths, all doc references.

### 2.1 Schema

`schema.sql`:
- `albums.browse_id VARCHAR(100) PRIMARY KEY` → `albums.id VARCHAR(100) PRIMARY KEY`
- FK reference `albums.browse_id` → `albums.id` (in `tracks.album_id` declaration, in `album_artists.album_id` declaration)
- The artist-style comment on the PK clarifies: `"-- YouTube 'MPREb_…' or curator-minted 'local_album_{uuid12}'"`

### 2.2 Production code

| File | What changed |
|---|---|
| `persistence/album_repository.py` | `find_by_browse_id()` → `find_by_id()`; SQL `a.browse_id` → `a.id` (4 SELECTs); return-shape keys `"browse_id"` → `"id"` (4 methods); function params `browse_id` → `album_id` (save_album, find_album_tracks, delete_album, update_cover_url, get_all_local_albums, search_albums) |
| `persistence/track_repository.py` | 5 `LEFT JOIN albums alb ON alb.browse_id = …` → `ON alb.id = …`; 1 docstring in `find_by_id` says `albums.id ← tracks.album_id` |
| `persistence/playlist_repository.py` | 3 `LEFT JOIN albums alb ON alb.browse_id = …` → `ON alb.id = …` (lines in get_favorites / get_tracks / get_history SELECTs) |
| `services/album_service.py` | Function params + locals + return-shape keys renamed; `queue_track_download` parameter renamed; docstrings updated |
| `services/search_service.py` | 4 sites: `al["browse_id"]` → `al["id"]` (local-album-row context) |
| `services/artist_service.py` | 2 sites: `album["browse_id"]` / `single["browse_id"]` → `"id"` (in `_shape_directory_row` style output) |
| `services/track_service.py` | `get_album_for_track` docstring — "Album browseId" → "Album id" |
| `routers/albums.py` | 3 path vars `/api/albums/{browse_id}` → `/api/albums/{album_id}` (detail, cover, download); function params + docstring text |
| `routers/curator.py` | Path `/api/curator/albums/{browse_id}/cover` → `{album_id}/cover`; local vars + response keys renamed |
| `routers/tracks.py` | Module docstring — "get album browseId for a track" → "get album id for a track" |
| `BACKFILL/13_verify.sql` | 2 SQL references `albums.browse_id` → `albums.id` (line 42 local-album check; line 53 FK-integrity check) |

### 2.3 Allowed YT-side references (intentionally NOT changed)

These are real YouTube Music API concepts, not the local DB row id:

| File | Symbol | Why kept |
|---|---|---|
| `utils/async_ytmusic.py` | `browse_id` parameter on `get_lyrics`, `get_album`, `get_song_related` | It's the API method-arg name in `ytmusicapi` |
| `services/yt_service.py` | `lyrics_browse_id`, `related_browse_id` | Local vars holding YT-side response identifiers |
| `services/search_service.py:246,259` | `item.get("browseId")` | camelCase JSON key from YT Music API |
| `services/artist_service.py:101,111` | `album.get("browseId")`, `single.get("browseId")` | camelCase JSON key from YT Music API |
| `services/search_service.py`, docstring | "lyrics browseId" | YT-side concept description |

### 2.4 Documentation sync

A consumer reading the docs should see the same names as the code:

**`API.md`** — 14 distinct edit operations, in three buckets (4 + 6 + 4 = 14):
- **4 endpoint paths renamed** — `/api/albums/{browse_id}` → `{album_id}` (detail), `/api/albums/cover/{browse_id}` → `{album_id}`, `/api/albums/download/{browse_id}` → `{album_id}`, `/api/curator/albums/{browse_id}/cover` → `{album_id}/cover`
- **6 response-field renames at 6 sites across 4 distinct JSON value patterns** — `"browse_id": "MPREb_nnFV6SxNfSN"` (2 sites: album detail, artist detail), `"browse_id": "MPREb_…"` (1 site: singles), `"browse_id": "local_album_a1b2c3d4e5f6"` (2 sites: curator-create response, curator-cover response), `"browse_id": "local_album_abc123def456"` (1 site: local-albums list response) — all to `"id"`
- **4 prose/URL renames** — `browse_id starts with local_album_` → `id starts with`; "Album browseId lookup" → "Album id lookup"; `Generates a local_album_{id} browse_id` → "album id"; the inline-URL inside the Background Bucket "Used by" (`POST /api/albums/download/{browse_id}` → `{album_id}`)

**`BACKEND_AGENT.md`** — 4 edits:
- §3.5 albums schema block — `browse_id VARCHAR PRIMARY KEY` → `id VARCHAR PRIMARY KEY`; removed `artists JSONB` / `tracks JSONB` (already dropped pre-Phase 4); added `is_curator BOOLEAN NOT NULL DEFAULT FALSE` discriminator + `album_artists` junction block
- §3.5 method list — `find_by_browse_id()` → `find_by_id()`; added `save_album()` and `find_album_tracks()` to the canonical method surface
- §3.9 tracks router table row — "Album browseId lookup" → "Album id lookup"
- §3.11 albums router — 4 endpoint paths renamed, `(browse_id starts with local_album_)` → `(id starts with local_album_)`

**Verify**:
```bash
grep -nF 'browse_id' API.md BACKEND_AGENT.md   # expect: nothing
grep -nF '"browseId": "UC' API.md              # expect: 1 line (YT JSON payload, kept)
```

---

## 3. Validation (after all three sections)

```bash
python3 -m compile-style parse over all 38 .py files  # → all OK
grep -nF 'browse_id' app/{persistence,services,routers,utils}/*.py   # → only YT-side whitelist
```

Code-reviewer posted `clean` verdict after the rename and again after the doc sweep.

---

## 4. Out of scope (documented for a future pass)

Deliberately **not** changed today — different in kind from the rename:

- `plan.md` / `plan2.md` — design-history documents from earlier phases. They reference `browse_id` and `local_artists` extensively as design history; rewriting them turns them into a different document. Leave until a deliberate "rewrite all docs" pass.
- `BACKEND_AGENT.md` §3.4 — tracks `CREATE TABLE` example still lists legacy `artists TEXT[]` / `artists_ids TEXT[]` / `album VARCHAR` columns dropped in **Phase 4** (different in kind; would be a Phase-4 doc pas, not part of the rename).
- `BACKEND_AGENT.md` §4 — schema commentary still references the `local_artists` table name + `idx_local_artists_lower_name` index, both renamed post-Phase 0/4. Same: separate doc pas.
- `lyrics_bug_report.html` / `backend_security_and_arch_report.html` — historical HTML reports.

---

## 5. Predecessor work (referenced, not republished)

Earlier in this iteration:

- **Phase 4** (per `plan2.md`) shipped before this session's changelog: dropped `tracks.artists` / `tracks.artists_ids` / `tracks.album` columns, replaced `idx_local_artists_lower_name` with partial unique index. Phase 4 status flipped to **Shipped** in `BACKFILL/README.md`.
- Wall-of-text docblock cleanup in `track_repository.py` / `playlist_repository.py` / etc. (per the user's earlier "direct and understandable comments" directive). Inline comments now 1-2 lines each, no `plan v2 §X.Y` cross-references in code.

---

## 6. Schema fix — extract `tracks` out of `artists`, lock the download-status union

**Before**: `schema.sql` declared the `artists` table with `id, name, bio, is_local` and then continued listing track-shaped columns (`title`, `album_id`, `track_number`, `disc_number`, `duration`, `is_local_upload`, `download_status`, `local_path`, `local_cover_path`, `local_lyrics_path`, `local_lrc_path`, `listen_count`, `created_at`) inside the same `CREATE TABLE` block. There was no separate `CREATE TABLE tracks`, even though `track_artists` referenced `tracks(id)` and every `TrackRepository` query used `FROM tracks / INSERT INTO tracks`. The schema was not loadable end-to-end — only the live DB saved by a previous init was "working."

`artists` was also missing `cover_path` and `created_at` despite `ArtistsDirectoryRepository.upsert` writing them on every call.

**After**: a proper `CREATE TABLE tracks (…)` block with `CHECK (download_status IN ('pending','downloading','completed','failed','discovered'))`. The union is the **canonical state machine** for `tracks.download_status` and the checksum that catches accidental future typos at the DB layer. `artists` is restored to its canonical six-column shape, with `cover_path` and `created_at` re-added.

### 6.1 Schema diff

| Location | Was | Is |
|---|---|---|
| `schema.sql` artists block | `id, name, bio, is_local` followed by track-shaped columns | `id, name, bio, is_local, cover_path, created_at` |
| `schema.sql` `tracks` block | (missing) | `id PK, title NOT NULL, album_id FK→albums(id) ON DELETE SET NULL, track_number, disc_number=1, duration, is_local_upload, download_status DEFAULT 'pending' CHECK IN (...), local_path, local_cover_path, local_lyrics_path, local_lrc_path, listen_count=0, created_at` |
| `schema.sql` indexes on tracks | `idx_tracks_album_id`, `idx_tracks_download_status`, `idx_tracks_album_track_number`, `idx_tracks_is_local_upload` — orphan | now backed by a real `tracks` table |

### 6.2 State machine (locked by CHECK)

| Value | Set when | Cleared when |
|---|---|---|
| `pending` | `create_pending` (default on insert) | `downloading` worker takes over |
| `downloading` | `_try_youtube_download` start | `completed` on success / `failed` on retry exhaustion |
| `completed` | download finished; `local_path` / `local_cover_path` / lyrics paths populated | (terminal) |
| `failed` | retry exhausted | next retry flips back to `pending` via `update_status_to_pending` |
| `discovered` | `create_discovered_batch` seed on album cache | single-track download flips to `pending` |

### 6.3 Verify

```bash
grep -nE "CREATE TABLE (artists|tracks)" schema.sql                              # expect: one of each
grep -nE "CHECK \(download_status" schema.sql                                    # expect: 1 hit
psql -f schema.sql 2>&1 | grep -E "ERROR.*tracks|ERROR.*artists"                 # expect: nothing on a fresh DB
```

---

## 7. Bug 1 fix — partial-album download populates the cache (the `discovered` state)

**Symptom**: open an album page → it shows 12 tracks → click *download* on ONE of them → re-open the album → only that one track is listed. The other 11 vanish until the next full re-fetch.

**Root cause**: `AlbumRepository.find_album_tracks` is `SELECT … FROM tracks WHERE t.album_id = %s`. The `tracks` table only had rows for tracks a user had actually queued for download. The cached album row (12 tracks of metadata) was correct, but `find_album_tracks` only echoed back what `tracks` knew about. A single download ⇒ a single row ⇒ the response collapsed to 1.

**After**: every album fetch seeds metadata-only `discovered` rows for ALL the album's tracks. `find_album_tracks` then returns the full 12 even before the user downloads anything, with `is_downloaded: false` on the 11 undiscovered ones. A single-track download promotes `discovered → pending → downloading → completed` via `create_pending`'s `ON CONFLICT (id) DO UPDATE SET download_status = 'pending'`.

### 7.1 New repository method

`persistence/track_repository.py::create_discovered_batch(tracks)` — bulk insert with `ON CONFLICT (id) DO NOTHING` for the rows and `ON CONFLICT (track_id, artist_id) DO NOTHING` for the `track_artists` junction, in a single transaction.

**Critical correctness property** — using `DO NOTHING` (not `DO UPDATE`) means re-caching an album never downgrades an already-completed or in-progress track back to `discovered`. The developers' initial instinct (UPSERT) would have silently erased `completed` rows on every cache refresh.

| Caller | Before fix | After fix |
|---|---|---|
| User opens album | metadata cached, 0 rows in `tracks` for that album | metadata + 12 `discovered` rows |
| User opens album, downloads track 3 | `tracks` row created for track 3 only | `create_pending` flips track 3 `discovered → pending`; the other 11 stay `discovered` |
| User opens album a third time | only track 3 returned (`album_id` FK) | all 12 returned; track 3 marked `is_downloaded: true`, others `false` |

### 7.2 New `AlbumService` helper

`services/album_service.py::_seed_discovered_tracks(album_id, resolved_tracks, album_artists)` runs after `AlbumRepository.save_album` so the FK on `tracks.album_id` is already satisfied.

Artist-resolution strategy (cheapest viable, no extra YT API calls):
1. Match each track-level artist name against the **album-level** artists list (we already have channel_ids for these from `is_local=FALSE` upserts in `fetch_and_cache_album`).
2. For names not on the album, batch-look-up by `LOWER(name)` via the new `ArtistsDirectoryRepository.find_youtube_ids_by_names` helper — returns only YouTube-sourced rows (`is_local=FALSE`).
3. Names not found anywhere are **dropped** from the junction. The track row is still written; the JOIN-fed `artists` array is `[]`, the front-end falls back to the album-level artists for display.

We deliberately do NOT mint `local_artist_{uuid12}` ids from album-fetch data — that would shadow future real YT-sourced rows for the same name. The user can wait for `get_track_metadata` to populate them correctly.

### 7.3 Reactive download controllers

Three call sites had to flip their "already seen" check to NOT short-circuit on `discovered`:

| File | Was | Is |
|---|---|---|
| `services/track_service.py::queue_download` | `if queued["download_status"] != "failed": return early` | only skip on `pending`/`downloading`/`completed`; treat `discovered` like `failed` and promote |
| `services/track_service.py::ensure_downloaded` | `if existing["download_status"] != "failed": return` | same fix |
| `services/album_service.py::queue_track_download` | `if existing["download_status"] != "failed": return False` | same fix |

For the `discovered → pending` transition the controllers now **reuse the row's existing metadata** (title, duration) so a single-track download does NOT require a fresh `get_track_metadata` YT call. They also pull the cover_url from `AlbumRepository.find_by_id(row["album_id"])` when the discovered row is FK-linked to an album — `handle_cover_cache` then finds the already-cached md5-keyed cover on disk instead of refetching from Google.

**Operationally critical ordering**: the album-cover lookup happens BEFORE `update_status_to_pending`. If the lookup raises (DB hiccup, pool exhaustion), the row stays in `discovered`/`failed` rather than wedging at `pending` with no background task scheduled.

### 7.4 Frontend-visible response change

`GET /api/albums/{album_id}` response: the `tracks[]` array now reflects all 12 (or N) album tracks. Each entry has `is_downloaded` and `download_status` keys:

```json
{
  "tracks": [
    { "video_id": "…", "title": "…", "artists": ["…"],
      "is_downloaded": true,  "download_status": "completed"  },
    { "video_id": "…", "title": "…", "artists": ["…"],
      "is_downloaded": false, "download_status": "discovered" }
  ]
}
```

`enrich_with_download_status` (existed pre-fix) already keys off `download_status='completed'`, so the `is_downloaded` flag is unchanged behaviour.

### 7.5 Verify

```bash
grep -nE 'create_discovered_batch' services/album_service.py persistence/track_repository.py   # expect: 2 hits (definition + call)
grep -nE '"discovered"' services/track_service.py services/album_service.py persistence/track_repository.py  # expect: ≥6 hits
psql -c "SELECT DISTINCT download_status FROM tracks"                # expect: union includes 'discovered'
```

---

## 8. Bug 2 fix — album covers no longer re-fetched from Google every render

**Symptom**: open an album → the cover image is loaded from `https://lh3.googleusercontent.com/…` (Google's CDN). Every picture render, every browser tab switch, every scroll-into-view = a round-trip to Google.

**Root cause**: `albums.cover_url` stored the remote URL and the album-detail response echoed it back unchanged. No local copy was ever written. `/api/albums/cover/{album_id}` only served curator-uploaded images (`album_{album_id}.{ext}`); auto-fetched covers didn't exist on disk at all.

**After**:
- `fetch_and_cache_album` eagerly calls `services.download_worker.handle_cover_cache(cover_url)` after `save_album`. The image lands at `THUMBNAILS_DIR/{md5(cover_url)}.jpg`. Identical covers across albums and tracks share disk via the md5 dedup already in `handle_cover_cache`.
- `GET /api/albums/{album_id}` response rewrites `cover_url` to `/api/albums/cover/{album_id}` whenever the local file exists. The remote raw URL stays in `albums.cover_url` for refresh logic.
- `GET /api/albums/cover/{album_id}` checks three paths in order: (1) curator-uploaded `album_{album_id}.{ext}`, (2) auto-cached `{md5(cover_url)}.jpg`, (3) lazy fetch from Google on first hit. Path (3) handles albums cached BEFORE this fix shipped.

### 8.1 New `AlbumService` cover helpers

| Method | Purpose |
|---|---|
| `find_album_cover_path(album_id)` | Path-only lookup; tries curator path then md5 hash; returns `None` if neither exists |
| `get_or_fetch_album_cover(album_id)` | Adds the lazy fetch: if neither path exists and `albums.cover_url` is set, calls `handle_cover_cache` and returns the result. Used by the router endpoint so legacy albums pick up coverage transparently |
| `_materialize_cover_url(album_id, raw_remote_url)` | Returns `/api/albums/cover/{album_id}` if the local file exists, else echoes `raw_remote_url`. Used by `get_album_detail` to do the response-shape substitution |

### 8.2 Why md5 instead of `album_{album_id}.jpg`

`handle_cover_cache` already uses md5(cover_url) as the on-disk name for **all** payload images (tracks AND albums). Reusing the same key:
- Allows an album cover and the per-track cover of the first song on that album to share one file on disk (they typically have the same URL).
- Lets `_materialize_cover_url` derive the path deterministically by re-hashing `albums.cover_url` without a separate "is it cached yet?" column.

The curator-upload convention `album_{album_id}.{ext}` is kept as a higher-priority lookup so a curator's custom cover still wins over an auto-fetched Google cover.

### 8.3 Response shape

```json
{  "id": "MPREb_…",
   "cover_url": "/api/albums/cover/MPREb_…"          // when local copy exists
   "cover_url": "https://lh3.googleusercontent.com/…"   // fallback
}
```

Front-ends consuming the old remote URL directly (e.g. avatar `<img src=…>` in some search/artist response paths) will still hit Google for now — see **§ 11. Out of scope** for the propagation follow-up.

### 8.4 Verify

```bash
grep -nE 'get_or_fetch_album_cover|_materialize_cover_url|handle_cover_cache' services/album_service.py  # expect: ≥3 hits
grep -nE 'find_album_cover_path' routers/albums.py services/album_service.py                            # expect: ≥2 hits
```

---

## 9. Concurrency & robustness hardening (folded into the bug-fix PR)

- `persistence/album_repository.py::save_album` now uses `ON CONFLICT (album_id, artist_id) DO NOTHING` on the `album_artists` insert, so two concurrent `fetch_and_cache_album` calls for the same album don't UniqueViolation. Both threads DELETE-then-INSERT the same `(album_id, artist_id)` tuples; first-write-wins on `position` is deterministic (positions are derived from the album-level artist list, both threads write the same value).
- `create_discovered_batch` filters tracks whose `title` is None or empty before the executemany. A single malformed YT track no longer rolls back the entire 12-track discovered batch — it's skipped with a `logger.warning` instead. The `tracks.title NOT NULL` constraint is preserved, and the bulk insert still aborts on a real type/format error.
- `services/track_service.py` now imports `AlbumRepository` at module level. The minor late-import dance inside `queue_download` / `ensure_downloaded` is gone. No circular-import risk (verified: `persistence.album_repository` only imports `persistence.db`, `logger`, `collections.Counter`).

---

## 10. Documentation sync

**`API.md`** — added a resolution-order paragraph on the `/api/albums/cover/{album_id}` endpoint describing (1) curator path, (2) md5-keyed cache hit, (3) lazy fetch. Stated the response-shape rule: `cover_url` is auto-rewritten to that endpoint whenever a local copy exists.

**`BACKEND_AGENT.md`** — expanded §3.5 (albums schema) with the new `tracks` table + the `CHECK` constraint union, plus a per-state reference table; updated the `ALBUM_TABLE` method surface (`find_by_id` replaces `find_by_browse_id`); added a note that `artists.cover_path` is null-tolerant on existing pre-fix rows.

---

## 11. Validation (after sections 6–10)

```bash
# Python source — every modified file parses cleanly
for f in persistence/track_repository.py persistence/album_repository.py persistence/artists_directory.py \
         services/album_service.py services/track_service.py routers/albums.py; do
  python3 -c "import ast; ast.parse(open('$f').read())" && echo "OK: $f" || echo "FAIL: $f"
done

# New 'discovered' touchpoints wired
grep -nE 'create_discovered_batch|discovered' services/album_service.py services/track_service.py persistence/track_repository.py  # expect: ≥ 8 hits

# Cover-URL rewrite flows through the album response, not just the cover endpoint
grep -nE '_materialize_cover_url|get_or_fetch_album_cover' services/album_service.py routers/albums.py  # expect: ≥ 3 hits

# CHECK constraint present on tracks.download_status
grep -nE "CHECK \(download_status" schema.sql                                       # expect: 1 hit
```

Code-reviewer posted `clean` verdict on the bulk of the change and on the polish pass (dead-code removal + import hoist + title-NULL guard).

---

## 12. Out of scope (documented for a future pass)

- **`SearchService` / `ArtistService` cover-URL rewrite** — the response-shape substitution in `_materialize_cover_url` only flows through `AlbumService.get_album_detail` today. Artist-detail and search results still echo the raw remote `cover_url`. Same pattern; needs to be threaded through consistently.
- **Live-DB migration** — the schema is "fresh-install only" per its header comment. Any deployment with a populated live DB needs a separate migration script that: extracts the existing tracks columns out of the artists mirror, drops them, CREATE TABLEs the canonical `tracks` shape, and adds `cover_path` / `created_at` to artists. Without it, `init_db()` would refuse to run against the existing DB.
- **Stale `cover_url` rotation cleanup** — if YT rotates `albums.cover_url` (same album id, different CDN URL), the md5-keyed local file is keyed off the OLD URL. `_materialize_cover_url` returns the new remote URL on stale-cache miss; `get_or_fetch_album_cover` re-fetches on the cover GET. Old local files become orphaned but never queried (cosmetic; ~200 KB per cover per rotation).
- **`ON CONFLICT DO NOTHING` metadata refresh** — documented limitation in `create_discovered_batch`'s docstring: re-caching an album does NOT refresh `title`/`duration` on existing `discovered` rows. `tracks.album_id` is also not re-pointed. Fine for v1; if correctness matters, change to `DO UPDATE SET title = CASE WHEN download_status='discovered' THEN EXCLUDED.title ELSE tracks.title END, …` to refresh only while still in the discovered state.
- **CHECK constraint expansion** — adding a future state (e.g. `retrying`, `paused`) silently violates the constraint unless someone updates the union. Worth tagging as a "needs schema-bump" in any future state-machine work.
