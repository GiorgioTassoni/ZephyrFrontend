# NewAPI.md — Zephyr backend changes, frontend-visible

> **Status:** Living document. Appended at the end of each implementation phase.
> **Audience:** Frontend devs integrating the Zephyr backend.
> **Scope:** Compile format of the conversation-phase changes (Phase 0 onwards).
> Each section is closed by a phase-end review from this repo's code-reviewer.
> **Out of scope:** Internal refactors, persistence schema migrations not exposed via the
> API, decisions that don't reach the frontend.

---

## Conventions (cumulative)

- **Polymorphic IDs** in browse-time responses:
  - `dz_<int>` — Deezer browse (introduced Phase 1).
  - `local_<uuid>` — curator-created records.
  - `UC…` — YouTube channel ids (legacy path).
- **Search responses still return raw Deezer integer IDs** (legacy contract preserved — Phase 0 lock).
- **Discriminators:** browse-time responses don't carry `is_local` (always false). Search responses do (mixes local + remote, the flag discriminates them).
- **Download state**, where applicable: `is_downloaded: bool` + `download_status: "completed"|"pending"|"downloading"|"failed"|"discovered"|null`. Always present on browse-time tracks; `null` / `false` until a click resolves the YT videoId (Phase 2).
- **`id` field is always a string.** Numeric IDs are wrapped in `dz_<int>` for browse-time; raw integers for search responses.
- **Duration**: seconds (`int`) for all Deezer-sourced responses; YouTube paths still return `"M:SS"` strings — renderers normalize if they want to mix.
- **`cover_url` is the only image key.** Browse-time shapes use `cover_url` for albums, artists, and playlists. Track-level art rides on `cover_art` for `parse_artist_top_song`'s dedup with album cover; tracks embedded in `parse_album_track` have no cover_art (it's read from the parent album's `cover_url`).
- **Phase 1 trim:** a number of fields were flagged as "noise" and dropped — see `Phase 1 — Trim notes` below for the diff intent.

---

## Phase 0 — RETROFITTED — Infra + Search migration

> This phase happened without `NewAPI.md` in place; documenting it retroactively.

### Settings (`config/settings.py`)

Three new env vars added to `Settings`:

| Env var | Default | Purpose |
|---|---|---|
| `DEEZER_DISCOVERY_ENABLED` | `True` | Feature flag. When `False` all Deezer calls short-circuit (search returns local-only; detail functions raise or zero-fill per the matrix below). |
| `DEEZER_RATE_PER_SECOND` | `8` | Sliding-window rate limit. Deezer's documented free-tier observed cap is ~50 req/5sec/IP; 8 req/s is conservatively under. |
| `DEEZER_HTTP_TIMEOUT` | `30.0` | `httpx.AsyncClient` request timeout (seconds). |

### Search endpoint changed: `GET /api/search`

**Before:** Local DB first, then YouTube Music fan-out (post-Phase-0, YT path removed).

**After:** Local DB first, then Deezer fan-out via `asyncio.gather`. Each Deezer call is rate-limited and retries on 429/5xx.

#### Response shape changes

- Removed: `has_remote` (boolean) — was always true when remote was queried.
- Added: `remote_source: "deezer" | "none"`. Self-documenting origin.

```jsonc
// NEW envelope
{
  "status": "success",
  "query": "...",
  "remote_source": "deezer",          // or "none" if local-only
  "summary": {
    "local_tracks": N,
    "tracks_count": N,
    "albums_count": N,
    "artists_count": N,
    "playlists_count": N
  },
  "results": {
    "tracks":    [track-shape, ...],
    "albums":    [album-shape, ...],
    "artists":   [artist-shape, ...],
    "playlists": [playlist-shape, ...]
  }
}
```

#### Track-shape changes (search responses)

| Field | Before | After |
|---|---|---|
| `id` | `video_id` (string) | `id` (string for local; raw int for remote Deezer) |
| `artists` (string) | `artists: "Artist A, Artist B"` | replaced with `artist_name: "Artist A, Artist B"` |
| — | — | new `artists_id: int` (single primary id, optional) |
| — | — | new `album_id: int` (optional) |
| — | — | new `cover_art: string \| null` |
| — | `album_art` (nullable always) | removed (use `cover_art`) |
| `is_downloaded` | bool | bool (unchanged) |
| `download_status` | enum | enum (unchanged, still surfaced for local hits) |

#### Playlist-shape changes

| Field | Before | After |
|---|---|---|
| — | `video_id` (always null on search) | removed |
| `id` | int | unchanged |
| `cover_url` | yes | yes (from Deezer CDN when remote source) |
| — | — | new `owner_name: string \| null` |

#### Artist-shape changes

| Field | Before | After |
|---|---|---|
| `avatar_art` | sometimes raw URL | always Deezer CDN URL when remote |
| `is_local` | bool | bool (unchanged) |

#### Album-shape changes

| Field | Before | After |
|---|---|---|
| `artist_name` | "Artist A, Artist B" | first artist only (singular) |
| `artist_id` | sometimes present | always present (Deezer int id) |
| `id` | sometimes string | consistent |
| `is_local` | bool | bool (always false for Deezer hits; local curator hits use `local_album_…`) |

### Backend infra (Phase 0)

- Shared module-level `httpx.AsyncClient` singleton (TCP/TLS keep-alive on).
- `SlidingWindowRateLimiter` — pure-Python sliding-window throttle (no external `aiolimiter` dep).
- 429 → doubles backoff (capped at 30s, retries 3x).
- 500/502/503/504 → exponential backoff (capped at 30s, retries 3x).
- `is_enabled()` short-circuits when `DEEZER_DISCOVERY_ENABLED=False`.
- New helper `download_deezer_cover(cover_url)` — md5-keyed cache (`THUMBNAILS_DIR/<md5>.jpg`) so Deezer-sourced covers share disk with existing curator covers.

### Behavior matrix when `DEEZER_DISCOVERY_ENABLED=False`

| Function | When disabled |
|---|---|
| `search_deezer` | returns `[]` |
| `get_album_detail` / `get_artist_detail` / `get_playlist_detail` / `get_track_detail` | raises `RuntimeError("Deezer discovery is disabled")` |
| `get_artist_albums` / `get_artist_top` / `get_album_tracks` / `get_playlist_tracks` | returns `{"data": []}` (zero-fill, no throw) |

---

## Phase 1 — NEW — Browse-time shape converters + service wiring

> **Status:** Backend live (Phase 1 deliverable shipped). Browse-endpoint routers NOT YET
> exposed — that's Phase 3. The backend service functions are wired and tested; no
> frontend-facing routes reach them yet.

### Phase 1 — Trim notes

After the first Phase 1 draft, a review pass dropped fields flagged as "noise":

| Shape | Dropped | Rationale |
|---|---|---|
| `parse_album_detail` | `label`, `year`, `duration_seconds`, `genres`, `fans`, `upc`, `downloaded_count`, `cached`, `is_local` | Year derivable from `release_date`; the rest are catalog metadata the frontend doesn't render. Browse-time is never locally cached or partially-downloaded. |
| `parse_album_detail.artists[]` | `channel_id` | Deezer has no channel_id equivalent; `null` is noise. |
| `parse_artist_detail` | `channel_id`, `share_url`, `avatar_art`, `is_local` | Consolidate on `cover_url` (one image key); drop the deep-link. |
| `parse_artist_album` | `year` | Redundant with `release_date`. |
| `parse_artist_top_song` | `album_art` | Duplicate of `cover_art`. Frontend uses `cover_art`. |
| `parse_playlist_detail` | `creator_id`, `creator_name`, `is_public`, `collaborative`, `share_url`, `duration_seconds`, `is_local` | Deezer browse playlists have no creator concept the frontend needs; everything else is constant (`is_public: true`) or dead-weight. |

`owner_name` on `parse_playlist_detail` is now the constant `"Deezer"` — the literal string, not a per-playlist creator name.

### New helpers — `utils/data_converter_utils.py`

| Helper | Purpose |
|---|---|
| `make_dz_id(int_id)` | Mint `"dz_<int>"` polymorphic identifier. |
| `parse_track_detail(raw)` | Deezer `/track/{id}` → single-track browse shape (superset of `parse_album_track`). |
| `parse_album_detail(raw)` | Deezer `/album/{id}` → slim album browse shape (with embedded first-page tracks). |
| `parse_artist_detail(raw)` | Deezer `/artist/{id}` → slim base artist shape. |
| `parse_playlist_detail(raw)` | Deezer `/playlist/{id}` → slim playlist browse shape. |
| `parse_album_track(raw)` / `parse_album_tracks(items)` | Single / listwise track within album context. |
| `parse_playlist_track(raw)` / `parse_playlist_tracks(items)` | Single / listwise track within playlist context. |
| `parse_artist_album(raw)` / `parse_artist_albums(items)` | Single / listwise album within artist's album list. |
| `parse_artist_top_song(raw)` / `parse_artist_top(items)` | Single / listwise song within artist's top list. |

### Browse-time response shapes (Phase 1 contract)

> **ID prefix:** every `id` field below is `"dz_<int>"` (e.g., `"dz_302127"` for Deezer album 302127).
> **Field count per shape:** album ~9, artist 5, playlist 7, track ~14. Slim by design.

#### `parse_track_detail(raw)` — single track, browse

```jsonc
{
  "id":               "dz_<int>",
  "title":            "...",
  "artist_name":      "Daft Punk",
  "artists":          ["Daft Punk", ...],           // deduplicated list
  "artist_id":        "dz_<int>",
  "album_id":         "dz_<int>",
  "duration":         320,                            // SECONDS
  "duration_seconds": 320,                            // duplicate of duration for renderer flexibility
  "position":         1,                             // track_position
  "preview_url":      "https://cdns-preview-...mp3", // 30s mp3 stream
  "video_id":         null,                           // resolved on click in Phase 2
  "is_downloaded":    false,                          // always at browse time
  "download_status":  null,                           // null at browse time
  "video_type":       null,
  "release_date":     "YYYY-MM-DD"|null,
  "bpm":              int|null,
  "is_explicit":      bool,
  "isrc":             "..."|null
}
```

#### `parse_album_detail(raw)` — album, browse

```jsonc
{
  "id":           "dz_<int>",
  "title":        "...",
  "album_type":   "album"|"single"|"ep"|"compilation",  // Deezer "compile" → "compilation"
  "release_date": "YYYY-MM-DD"|null,                    // year can be derived from this
  "artist_name":  "...",                                // primary, for card headers
  "artists":      [{"name": "...", "id": "dz_<int>"}],  // slim: no channel_id
  "track_count":  14,
  "cover_url":    "https://...",
  "tracks":       [album-track-shape, ...]              // first page from album doc
}
```

#### `parse_artist_detail(raw)` — artist, browse (base only)

Albums + top are fetched separately via `get_artist_albums` and `get_artist_top`. This
call returns the base shape only.

```jsonc
{
  "id":          "dz_<int>",
  "name":        "...",
  "cover_url":   "https://...",       // Deezer picture_xl
  "fans":        54321|null,          // Deezer's "nb_fan"
  "album_count": 9|null               // Deezer's "nb_album"
}
```

#### `parse_artist_albums(items)` — albums within artist

```jsonc
[{
  "id":           "dz_<int>",
  "title":        "...",
  "release_date": "YYYY-MM-DD"|null,
  "cover_url":    "https://..."|null
}]
```

Service returns `{"data": [...], "total": N}`.

#### `parse_artist_top(items)` — top songs within artist

```jsonc
[{
  "id":               "dz_<int>",
  "title":            "...",
  "duration":         320,
  "duration_seconds": 320,
  "position":         1|null,                         // rank
  "artist_name":      "...",
  "artist_id":        "dz_<int>",
  "album_id":         "dz_<int>",
  "album_title":      "...",
  "cover_art":        "https://...|null",             // album cover; same key as ALBUM cover_url but tracks dedupe against album_art
  "preview_url":      "https://...mp3"|null,
  "is_downloaded":    false,
  "download_status":  null,
  "video_id":         null                            // Phase 2 resolves on click
}]
```

Note: `cover_art` is the only image key for top tracks (no `album_art` alias). The album cover URL inside the parent album is at `album.cover_url`.

#### `parse_playlist_detail(raw)` — playlist, browse

```jsonc
{
  "id":          "dz_<int>",
  "title":       "...",
  "description": "..."|null,
  "owner_name":  "Deezer",                            // constant — Deezer browse playlists have no creator concept
  "track_count": int,
  "cover_url":   "https://...",
  "tracks":      [playlist-track-shape, ...]         // first page from playlist doc
}
```

#### `parse_album_track(raw)` / `parse_playlist_track(raw)` — nested track

```jsonc
{
  "id":               "dz_<int>",
  "title":            "...",
  "artist_name":      "..."|null,                   // primary
  "artists":          ["...", ...],                 // deduplicated list
  "artist_id":        "dz_<int>"|null,
  "album_id":         "dz_<int>"|null,
  "duration":         320,
  "duration_seconds": 320,
  "position":         1|null,                       // track_position
  "preview_url":      "https://...mp3"|null,        // 30s mp3 preview (album tracks only carry this when Deezer has it)
  "video_id":         null,                         // resolved on click in Phase 2
  "is_downloaded":    false,
  "download_status":  null,
  "video_type":       null
}
```

### Routes affected by Phase 1 (no new routes yet)

Phase 1 added the converters and wired them into `services/deezer_service.py`. The
**browse endpoints** (`/api/albums/deezer/{id}`, `/api/artists/deezer/{id}`,
`/api/playlists/deezer/{id}`, `/api/tracks/deezer/{id}`) are **NOT YET exposed** —
that's Phase 3. For now, only the Phase-0 `/api/search` endpoint returns Deezer data.

### Type signatures — note for backend integrators

The Phase 1 service functions take `int` IDs:

```python
get_track_detail(track_id: int) -> dict[str, Any]
get_album_detail(album_id: int) -> dict[str, Any]
get_artist_detail(artist_id: int) -> dict[str, Any]
get_playlist_detail(playlist_id: int) -> dict[str, Any]
```

Deezer IDs in the polymorphic `dz_<int>` form need stripping before calling. The
helper `make_dz_id` does minting; for unminting (when Phase 3 ships), use a simple
strip on `"dz_"` prefix. Phase 3 will move these to `str | int` union signatures
to accept both forms.

### Test surface (Phase 1)

`tests/test_deezer_service.py` covers, with shape-frozen assertions via
`set(out.keys()) == expected_keys`:

- `make_dz_id(42) == "dz_42"`, `make_dz_id(None) is None`.
- `parse_track_detail` happy-path + missing-fields tolerance + `dz_<int>` minting.
- `parse_album_detail` shape lock: 9 keys only (no `label` / `year` / etc).
- `parse_album_detail` normalises Deezer's `"compile"` record_type → `"compilation"`.
- `parse_artist_detail` shape lock: 5 keys only (`id, name, cover_url, fans, album_count`).
- `parse_playlist_detail` shape lock: 7 keys only with `owner_name == "Deezer"` constant.
- `parse_artist_album` shape lock: 4 keys (no `year`).
- `parse_artist_top_song` shape lock: no `album_art`, only `cover_art`.
- End-to-end async: `get_album_detail`, `get_artist_top`, `get_album_tracks` pagination, `get_artist_albums` paginated preserve-total.

### Behavior matrix when `DEEZER_DISCOVERY_ENABLED=False`

Same matrix as Phase 0 (above). No additions in Phase 1.

---

## Phase 2 — NEW — Click-time Deezer resolve + download

> **Status:** Backend live (Phase 2 deliverable shipped). Service-layer dispatch is wired and
> tests cover the four critical branches. `/api/tracks/stream/{video_id}` is intentionally
> NOT extended yet — that's Phase 7 work if we ever need streamed playback off a `dz_<int>`.

### Phase 2 — Trim intent

Locked with the user before implementation:

- **Surface:** Option B — extend existing endpoints (`POST /api/tracks/download/{id}`,
  `POST /favorites/{track_id}`, `POST /playlists/{id}/tracks`) to accept either a YT
  videoId OR a `dz_<int>`. Dispatch lives inside `TrackService.ensure_downloaded` /
  `queue_download` (the canonical queue boundary per their docstrings). No new endpoint.
- **Resolve miss:** locked Q2 answer — `find_audio_version` returns None ⇒
  `DeezerResolveError` ⇒ router maps to **422 Unprocessable Entity**.

### New module — `utils/id_dispatch.py`

Polymorphic-id bridge between the API boundary and the canonical queue boundary.

```python
def is_dz_id(track_id: str) -> bool                    # dz_ prefix?
def strip_dz(track_id: str) -> int | None             # parse int suffix
class DeezerResolveError(Exception): ...               # mapped to 422 at routers
class ResolvedTarget(video_id, deezer_track_meta=None,
                    cover_url=None, title=None,
                    duration_seconds=None,
                    artist_name=None, album_id=None)
async def resolve_target_id(track_id: str) -> ResolvedTarget
```

| Input | Behaviour |
|---|---|
| Plain YT format (`UC...`) | Passthrough. `ResolvedTarget(video_id=<input>)` with no Deezer fields. |
| `dz_<int>` (clean) | 1 Deezer detail fetch + 1 YT `find_audio_version`. Returns `ResolvedTarget` with `deezer_track_meta` populated for downstream persistence; `video_id` is the resolved YT id. |
| `dz_<int>` (invalid suffix, e.g. `dz_abc`) | Raises `DeezerResolveError("Invalid Deezer browse id")`. |
| `dz_<int>` with no Deezer title | Raises `DeezerResolveError("Deezer track X returned without a title")`. |
| `dz_<int>` with no ATV match on YT | Raises `DeezerResolveError("No audio-only version on YouTube for ...")` — locked Q2 answer. |

### Persistence on a Deezer click (new track row)

When a `dz_<int>` resolves and the YT id has no row yet, `TrackService` writes:

| Field | Value |
|---|---|
| `tracks.id` | Resolved YT videoId (from `find_audio_version.videoId`). |
| `tracks.title` | Deezer track title. |
| `tracks.album_id` | `"dz_<deezer_album_id>"` — soft FK, no `albums` row stub. |
| `tracks.duration` | Deezer seconds. |
| `tracks.display_artist` | Deezer primary artist name (`Daft Punk` etc.) — fallback display copy when no `track_artists` junction is rendered. |
| `tracks.download_status` | `'pending'` → worker flips to `'completed'`. |
| `artists.id` (directory) | `"dz_<deezer_artist_id>"`, `is_local=TRUE` — Deezer is the only source we have right now. Future Phase 5 backs this with YT channel ids when present; the polymorphism means the directory row key stays stable across migrations. |
| `track_artists` junction | `[dz_<artist_id>]` (single primary artist row). |

### Side-effect: `handle_cover_cache` is now domain-aware

`/api/tracks/download/{id}` passes the resolved `cover_url` through to the background
worker, which calls `handle_cover_cache`. Before this phase, that helper unconditionally
appended YouTube's `=w544-h544-l90-rj` sizing suffix to any URL without `=w` — Deezer CDN
URLs (`https://cdns-preview-X.dzcdn.net/...`) were being mangled into broken URLs. The fix:
only append the YT sizing suffix when the URL contains `ytimg.com`, `youtube.com`, or `=w`.
Non-YT CDNs (Deezer cover_xl, generic) pass through verbatim. Backwards-compatible with
all existing YT URLs.

### Endpoint contract change

| Endpoint | Before | After |
|---|---|---|
| `POST /api/tracks/download/{video_id}` | YT videoId only | Accepts `dz_<int>`. Dispatches inside `TrackService.queue_download(track_id)`. |
| `POST /api/favorites/{track_id}` (with `track_id` path param) | YT videoId only | Accepts `dz_<int>`. Dispatches inside `TrackService.ensure_downloaded(track_id)`. |
| `POST /api/playlists/{id}/tracks` (body `{track_id}`) | YT videoId only | Accepts `dz_<int>`. Routes through `PlaylistService.add_track` → `ensure_downloaded`. |
| `POST /api/tracks/stream/{video_id}` | YT videoId only | **Unchanged** (Phase 7 candidate for browse-stream UX). |

### Error mapping (routers)

| Condition | HTTP | Body |
|---|---|---|
| `DeezerResolveError` (resolve miss, invalid id, no title) | **422** | `detail="Could not resolve browse track to a YouTube version: ..."` |
| Other `Exception` from the dispatch (DB fail, YT client unavailable, etc.) | **500** | unchanged |

Catches are placed AHEAD of the generic `except Exception:` in each router so the 422
fires before the 500 fallback. The `except HTTPException:` re-raise keeps the
playlist-not-found 404 from getting swallowed by the Deezer handler.

### Test surface (Phase 2)

`tests/test_id_dispatch.py` — unit tests, no DB:
- `is_dz_id` (varied inputs), `strip_dz` (integer parse + invalid suffix).
- `resolve_target_id` YT passthrough (no Deezer touched).
- `resolve_target_id` `dz_` happy path (mocks `services.deezer_service.get_track_detail`
  + `services.yt_service.find_audio_version`).
- Each error branch: invalid id, no title, ATV miss, empty videoId in match dict.

`tests/test_track_service_phase2.py` — service-layer + DB:
- `ensure_downloaded('dz_<int>')` happy path → row persisted with `id=videoId`,
  `album_id='dz_<deezer_album_id>'`, `display_artist`, `duration`, and an artists
  directory row at `is_local=TRUE`.
- `ensure_downloaded('dz_<int>')` resolve-miss → `DeezerResolveError`, no row written.
- `ensure_downloaded('UC...')` YT passthrough regression (uses conftest's
  pre-mocked `yt_user.get_song`).
- Idempotency: a second click with the same `dz_<int>` does NOT re-dispatch (mock
  call counts verify the singleton path through `find_by_id_any_status`).
- `queue_download('dz_<int>')` happy path → returns the same queued shape with
  resolved videoId.
- `_upsert_dz_artist` direct unit tests (happy / no artist_id / no artist_name).

---

## Phase 3 — NEW — Deezer album view (JSONB-cached tracklist)

> **Status:** Backend live (album view shipped). Artist + playlist + single-track
> views still in design — see "Open questions" below.

### Endpoint (unchanged shape, polymorphic dispatch)

The existing `GET /api/albums/{album_id}` accepts any of three id shapes:

| `album_id` | Source | Service dispatch |
|---|---|---|
| `dz_<int>` (e.g. `dz_302127`) | Deezer browse | `AlbumService._get_deezer_album_detail` (Phase 3 path) |
| `local_album_<uuid12>` | Curator-created | `AlbumService.fetch_and_cache_album` (legacy curator path) |
| `MPREb_…` (legacy YT browseId) | YouTube Music | `AlbumService.fetch_and_cache_album` (legacy YT path) |

Same URL, three code paths. Frontend never needs to branch on the id shape —
just `GET /api/albums/{whatever_the_browse_returned}`.

Query params:
- `?refresh=true` — bypasses the JSONB cache and re-fires Deezer for `dz_<int>`
  ids. The legacy path already accepted this; Phase 3 wires the Deezer branch
  to the same semantic (re-fetch and overwrite the cached row).

### Cache layer — `albums.tracks_cache JSONB`

`schema.sql` adds a single column to `albums`:

```sql
tracks_cache JSONB DEFAULT NULL,
-- Idempotent column-add for DBs that came up before the column existed.
ALTER TABLE albums ADD COLUMN IF NOT EXISTS tracks_cache JSONB DEFAULT NULL;
```

The slim `parse_album_detail` payload (title + cover + artist list + first-page
tracks) is persisted verbatim under `tracks_cache` on first browse. Re-opening
re-browsing hits the JSONB cache directly — **0 Deezer calls** after the first
read. The legacy YT/curator rows keep `tracks_cache = NULL`; their caching path
is unchanged.

### Response shape — enriched slim + aggregate

```jsonc
{
  "id":              "dz_302127",
  "title":            "Discovery",
  "album_type":       "album" | "single" | "ep" | "compilation",
  "release_date":     "2001-03-07" | null,
  "artists":          [{"name": "Daft Punk", "id": "dz_27"}, ...],
  "artist_name":      "Daft Punk",                     // primary, for card headers
  "track_count":      14,
  "cover_url":        "https://cdns-...drieveryrial.jpg",
  "downloaded_count": 3,                              // AGGREGATE — count of completed tracks
  "tracks": [
    {
      "id":               "dz_3135551",
      "title":            "One More Time",
      "artist_name":      "Daft Punk",
      "artists":          ["Daft Punk", ...],
      "artist_id":        "dz_27",
      "album_id":         "dz_302127",
      "duration":         320,
      "duration_seconds": 320,
      "position":         1,
      "preview_url":      "https://cdns-preview-...m4a",   // 30s mp3 (when Deezer has it)
      "video_id":         null,                              // resolved on click in Phase 2
      "is_downloaded":    false,
      "download_status":  null,                              // null|completed|pending|downloading|failed|discovered
      "video_type":       null
    },
    ...
  ]
}
```

**Field delta vs. raw `parse_album_detail`:**
- Adds `downloaded_count` (top-level aggregate).
- Adds `is_downloaded` and `download_status` on every track (Phase 2 carries these
  through title-match enrichment).
- Drops `cached` (always true once browsed; redundant with the JSONB cache).
- Drops `year` (not in Phase 1 slim; derivable from `release_date` on render).
- Drops `downloaded_count` is NOT marked "noise" — it's the only UI affordance
  the album header needs to show "X of 14 downloaded".

### Title-match enrichment caveat

Download status on each track is computed by matching on `LOWER(title)` between
the cached Deezer tracklist and the `tracks` table where `tracks.album_id =
'dz_<int>'`. Two tracks with the same title on the same album collide → both
report the same status. Collision rate for Deezer-cataloged albums is low (the
catalog rarely repeats a title within one album); the visual UI tolerates it
for click navigation. Future phases could split on `(album_id, title,
track_position)` once `tracks.track_number` is forward-filled at click time.

### Side-effect: NO `_seed_discovered_tracks` for Deezer paths

The legacy YT `fetch_and_cache_album` calls `_seed_discovered_tracks` to
bulk-insert `discovered` rows in the `tracks` table (so cache hits return the
full tracklist with `is_downloaded: false` for the unclicked 11 of 12).
**`tracks.id` is a YouTube videoId** — there's no such thing for unclicked
Deezer tracks. We deliberately DON'T seed `discovered` rows for `dz_<int>`
albums. The cached Deezer tracklist lives in `albums.tracks_cache` JSONB
instead, and is the source of truth at browse-time.

This shape stays consistent with the rest of the app because:
- `tracks` only contains videos we have actually resolved → audio-ready.
- `albums.tracks_cache` carries the full Deezer catalog for browse-time display.
- `_seed_discovered_tracks` is RETAINED for the legacy YT path (legacy
  rows still rely on it for the same-origin cache-hit behaviour).

### Routing — `/albums/{album_id}`

`routers/albums.py` is unchanged. The polymorphic-dispatch pattern means
`GET /api/albums/dz_302127` already routes to `AlbumService.get_album_detail`,
which detects the `dz_` prefix inside and dispatches to Phase 3's branch. No
router-level changes needed.

### Implementation footprint

| File | Change |
|---|---|
| `schema.sql` | + `tracks_cache JSONB DEFAULT NULL` column + idempotent `ALTER TABLE ADD COLUMN IF NOT EXISTS`. |
| `persistence/album_repository.py` | + `save_deezer_album(dz_id, payload)` UPSERT; + `find_dz_album_track_statuses(album_id, titles_lower)` title-match batch; `find_by_id` surfaces `tracks_cache` as a parsed dict. |
| `services/album_service.py` | + `is_dz_id` import; `get_album_detail` polymorphic dispatch; + `_get_deezer_album_detail` (cache → Deezer → bulk-upsert artists → save with tracks_cache → enrich); + `_enrich_dz_album_tracklist_with_download_status` title-match helper. |
| `tests/test_album_service_phase3.py` | NEW. 9 tests: cache miss → Deezer fires; cache hit → no Deezer; refresh forces fetch; title-match enrichment (pos + neg); `downloaded_count` derives correctly; `_seed_discovered_tracks` SKIPPED; `save_deezer_album` JSONB round-trip; `find_dz_album_track_statuses` direct query; polymorphic dispatch. |
| `NewAPI.md` | This section. |

### Test surface (Phase 3)

`tests/test_album_service_phase3.py` covers:
- `test_dz_album_cache_miss_fires_deezer_and_persists` — `dz_<int>` rows write through.
- `test_dz_album_cache_hit_skips_deezer` — second browse is 0 Deezer calls.
- `test_dz_album_refresh_forces_fetch` — `?refresh=true` bypasses cache.
- `test_dz_album_enrichment_title_match_marks_downloaded` — `tracks.album_id='dz_<int>'` +  status='completed' surfaces as `is_downloaded=True`.
- `test_dz_album_enrichment_no_match_yields_zero_downloaded` — DB has no tracks against `dz_<int>` → `downloaded_count=0`.
- `test_dz_album_does_not_seed_discovered_tracks` — defensive regression: the dispatcher must NOT pre-populate `tracks` rows with `download_status='discovered'`.
- `test_save_deezer_album_round_trips_jsonb` — payload survives the JSONB column round-trip.
- `test_find_dz_album_track_statuses_returns_lower_title_keyed_map` — direct query.
- `test_get_album_detail_dz_dispatch_is_polymorphic` — `dz_<int>` ids skip the YT path entirely.

---

## Phase 4 — NEW — Deezer artist view (stateless browse)

> **Status:** Backend live (artist view shipped). Single-artist scope locked —
> no related-artist fan-out. Phase 5 (playlist) is the natural next dispatch.

Phase 4 is **stateless** per the user's delegation ("re-fetch on each view is
acceptable"). The dispatcher fires 3 Deezer round-trips in parallel for every
view; no JSONB cache, no DB write. The cache strategy that worked for albums
(Phase 3) is intentionally NOT applied here — iterative artist browse is
fast enough on Deezer's side that cache-write atomicity issues would outweigh
the saved call.

### Endpoint (unchanged shape, polymorphic dispatch)

The existing `GET /api/artists/{channel_id}` now accepts any of three id shapes:

| `channel_id` | Source | Service dispatch |
|---|---|---|
| `dz_<int>` (e.g. `dz_27`) | Deezer | `ArtistService._get_deezer_artist_detail` (Phase 4 path) |
| `UC...` | YouTube Music | `ArtistService._get_yt_artist_detail` (legacy) |
| `local_artist_<uuid12>` | Curator-created | `ArtistService.get_local_artist_detail` (legacy) |

Same URL; three code paths. Frontend never needs to branch on the id shape.
The 503 YT-unavailable guard is now scoped to non-`dz_` ids so Deezer browse
isn't blocked by a missing YT client.

### Response shape (Phase 4 contract — minimal slim)

```jsonc
{
  "id":          "dz_<int>",
  "name":        "Daft Punk",
  "fans":        int | null,                 // Deezer's "nb_fan"
  "album_count": int | null,                 // Deezer's "nb_album"
  "cover_url":   "https://cdns-...artist.jpg",  // Deezer picture_xl
  "albums":      [slim-album, ...],
  "top_songs":   [slim-top-song, ...]
}
```

#### `albums[]` shape (Deezer)
```jsonc
[{
  "id":           "dz_<int>",
  "title":        "...",
  "release_date": "YYYY-MM-DD" | null,
  "cover_url":    "https://..." | null
}]
```

#### `top_songs[]` shape (Deezer; no per-track download state)
```jsonc
[{
  "id":               "dz_<int>",
  "title":            "...",
  "duration":         int | null,
  "duration_seconds": int | null,             // duplicate for renderer flexibility
  "position":         int | null,           // rank / canonical order
  "artist_name":      "Daft Punk" | null,
  "artist_id":        "dz_<int>" | null,
  "album_id":         "dz_<int>" | null,
  "album_title":      "Discovery" | null,
  "cover_art":        "https://..." | null,
  "preview_url":      "https://...m4a" | null,    // 30s mp3
  "is_downloaded":    false,                    // ALWAYS at browse; FE re-fetches via /api/tracks/{id}
  "download_status":  null,
  "video_id":         null
}]
```

**Field delta vs. Phase 1's `parse_artist_top_song`:**
**Same.** The minimal-slim pick means we do **not** add `is_downloaded` /
`download_status` enrichment even though the `tracks.album_id = dz_<int>` +
`tracks.title` join would be cheap. The FE re-fetches per-track status from
the existing `/api/tracks/{id}/status` endpoint when a song is opened — keeps
the artist payload light, matches the user's minimal-slim rule for Phase 4.

### Single-artist scope (locked)

We never call `get_artist_related(...)` and never expose `related_artists` in
the response shape, even if it surfaces from Deezer. The artist-detail view
shows ONLY the opened artist's metadata + tracks + albums. Clicking another
artist in the UI is a separate browse call.

### 3 round-trips per view (in parallel)

```python
base, albums_block, top_block = await asyncio.gather(
    deezer_service.get_artist_detail(deezer_int_id),
    deezer_service.get_artist_albums(deezer_int_id, limit=25, index=0),
    deezer_service.get_artist_top(deezer_int_id, limit=10),
)
```

`asyncio.gather` cuts the wall time to ~max(3 calls) instead of sum. Limits
are:
- `albums`: first 25 (one page of Deezer's `/artist/{id}/albums`).
- `top_songs`: first 10.

Future pages can be added with `?page=N` if the FE needs pagination.

### 503 parity

`routers/artists.py:get_artist_detail` mirrors the Phase 3 / Phase 4 album
pattern:
1. The YT-availability guard skips for `dz_` ids (`not channel_id.startswith("dz_")`).
2. The catch surface routes `DeezerUnavailableError → HTTPException(503)`
   ahead of generic `except Exception`.

Users see consistent 503 semantics across both browse-time resources.

### Implementation footprint

| File | Change |
|---|---|
| `services/artist_service.py` | Module docstring updated for Phase 4; top-of-class polymorphic dispatcher at `get_artist_detail`; `_get_deezer_artist_detail` (stateless fan-out); legacy YT method renamed to `_get_yt_artist_detail`. Local-artist methods unchanged. |
| `routers/artists.py` | YT 503 guard now skipped for `dz_` ids; `DeezerUnavailableError → 503` mapping ahead of generic except. |
| `tests/test_artist_service_phase4.py` | NEW. 6 tests: minimal-slim shape; 3 Deezer calls fan-out via `asyncio.gather`; 503 mapping; single-artist scope; polymorphic dispatch (both directions: `dz_` → Deezer, `UC` → YT). |
| `NewAPI.md` | This section. |

### Test surface (Phase 4)

`tests/test_artist_service_phase4.py` covers:
- `test_dz_artist_returns_minimal_slim_shape` — locks the 7-field top-level shape and the 4-field albums shape from `parse_artist_albums`.
- `test_dz_artist_fires_three_deezer_calls_per_view` — `assert_called_with(27)` confirms `dz_27` strips correctly.
- `test_dz_artist_raises_deezer_unavailable_when_disabled` — disabled-flag lock.
- `test_dz_artist_single_artist_scope_no_related` — defensive regression test: even if Deezer returns `related_artists` in the base detail call, our dispatcher ignores it.
- `test_artist_dispatch_routes_dz_to_deezer_branch` — `dz_` ids skip YT; YT mocks never called.
- `test_artist_dispatch_routes_uc_to_yt_legacy` — `UC` ids skip Deezer; Deezer mocks never called.

---

## Phase 5 — NEW — Deezer playlist view (stateless browse + title-match enrichment)

> **Status:** Backend live (playlist view shipped). Mirrors Phase 4's
> stateless strategy + Phase 3's enriched-slim response. Browse-time
> cover remains raw remote URL (no eager local cache) — cache writes
> happen for free once any track on the playlist is downloaded.

Phase 5 resolves the **stateless + enriched** combination the user
explicitly chose:

- **Cache**: stateless — 1 Deezer roundtrip per view (`get_playlist_detail`
  embeds first-page tracks in the playlist doc itself), no DB write.
- **Enrichment**: title-match batch query against
  `tracks.album_id = dz_<int>` + `LOWER(title)` adds `is_downloaded`
  + `download_status` per track + a top-level `downloaded_count`
  aggregate.

### Endpoint (unchanged shape, polymorphic dispatch)

The existing `GET /api/playlists/{playlist_id}` accepts two id shapes:

| `playlist_id` | Source | Service dispatch |
|---|---|---|
| `dz_<int>` (e.g. `dz_90819`) | Deezer browse | `PlaylistService._get_deezer_playlist_detail` (Phase 5 path) |
| integer (e.g. `42`) | Local curator/legacy | `PlaylistService.get_playlist_with_tracks` (existing ownership gate) |

Same URL; two code paths. Frontend never branches on the id shape. The
local `playlists.id` column is `INTEGER` already, so legacy local
playlists continue to use bare integer ids; Deezer browse uses the
`dz_<int>` polymorphic prefix introduced in Phase 1.

### Mutating endpoints — natural reject via FastAPI

`POST /api/playlists/{id}/cover`, `POST /api/playlists/{id}/tracks`,
`PUT /api/playlists/{id}/tracks/reorder`, `DELETE /api/playlists/{id}/tracks`,
`PUT /api/playlists/{id}`, `DELETE /api/playlists/{id}` — these keep
`playlist_id: int` typing. A `dz_` string passed to any of them is
naturally rejected by FastAPI with a **422** before our handler runs.
We never want to mutate a remote browse resource — the local
ownership model has no meaning for Deezer browse playlists.

### Response shape — enriched slim + aggregate

```jsonc
{
  "id":               "dz_90819",
  "title":            "Daft Punk Essentials",
  "description":      "Hand-picked tracks" | null,
  "owner_name":       "Deezer",                     // constant — see Phase 1 trim notes
  "track_count":      42,                            // Deezer's catalog total
  "cover_url":        "https://cdns-.../playlist.jpg",
  "downloaded_count": 7,                             // AGGREGATE — count of completed tracks
  "tracks": [
    {
      "id":               "dz_3135551",
      "title":            "One More Time",
      "artist_name":      "Daft Punk",
      "artists":          ["Daft Punk", ...],
      "artist_id":        "dz_27",
      "album_id":         "dz_302127",
      "duration":         320,
      "duration_seconds": 320,
      "position":         1 | null,
      "preview_url":      "https://cdns-preview-...m4a" | null,    // 30s mp3
      "video_id":         null,                                    // resolved on click in Phase 2
      "is_downloaded":    false,
      "download_status":  null | "completed" | "pending" | "downloading" | "failed" | "discovered",
      "video_type":       null
    },
    ...
  ]
}
```

**Field delta vs. raw `parse_playlist_detail`:**
- Adds `downloaded_count` (top-level aggregate).
- Adds `is_downloaded` and `download_status` on every track (Phase 2
  row carries these through title-match enrichment; `discovered`/
  `pending` show the click-pending state truthfully).
- Drops nothing — Phase 1 already trimmed Deezer playlists to the 7
  base keys.

### Title-match enrichment caveat

`is_downloaded`/`download_status` per track is computed by matching the
Deezer playlist tracklist on `(tracks.album_id = dz_<int>, LOWER(title))`
against the local `tracks` table. Two Deezer tracks with the same
title on the same Deezer album collide on the title key → both report
the same status. Collision rate for Deezer-catalogued playlists is
low.

### 503 parity

`routers/playlists.py:get_playlist` mirrors the Phase 3 / Phase 4 pattern:

1. The `DeezerUnavailableError → HTTPException(503)` catch is placed
   AHEAD of the generic `except Exception` (which is now removed for
   this endpoint — failures map to 503 / 404 only).
2. Local-path failures use the existing 404 gate (None → not found).

Users see consistent 503 semantics across all Phase 3-5 browse-time
resources.

### Implementation footprint

| File | Change |
|---|---|
| `persistence/track_repository.py` | + `find_dz_playlist_track_statuses(pairs)` batch query using parallel `unnest` arrays — keyed by `(album_id, lower(title))`, returns `download_status` (None for missing). |
| `services/playlist_service.py` | + `get_playlist_detail(playlist_id: str, user_id: int)` polymorphic dispatcher; `_get_deezer_playlist_detail(dz_playlist_id)` stateless 1-roundtrip browse; `_enrich_dz_playlist_tracklist_with_download_status` title-match helper. Existing `get_playlist_with_tracks` / ownership gate unchanged. |
| `routers/playlists.py` | `GET /playlists/{playlist_id}` parameter retype `int` → `str`; dispatcher moved from `int`-bound `get_playlist_with_tracks` to polymorphic `get_playlist_detail`; `DeezerUnavailableError → HTTPException(503)` added. Mutate endpoints keep `int`. |
| `tests/test_playlist_service_phase5.py` | NEW. 8 tests: enriched-slim shape; title-match enrichment (positive + zero-match); single Deezer roundtrip lock; 503-disabled mapping; pair-shape sent to repo; int passthrough to local; non-numeric → None. |
| `NewAPI.md` | This section. |

### Test surface (Phase 5)

`tests/test_playlist_service_phase5.py` covers:
- `test_dz_playlist_returns_enriched_slim_shape` — locks the 8 top-level
  fields + per-track `is_downloaded`/`download_status`.
- `test_dz_playlist_enrichment_title_match_marks_downloaded` — mixed
  status map → `is_downloaded=True` only on `completed`; `downloaded_count`
  reflects the count.
- `test_dz_playlist_enrichment_no_match_yields_zero` — empty status map
  → all `is_downloaded=False`, `downloaded_count=0`.
- `test_dz_playlist_fires_single_deezer_call_no_db_write` — stat counter
  on the wrapper mock + read-only mock on the title-match helper.
- `test_dz_playlist_raises_deezer_unavailable_when_disabled` —
  `DEEZER_DISCOVERY_ENABLED=False` raises `DeezerUnavailableError`.
- `test_enrichment_called_with_correct_pairs` — verify the repository
  receives the correct `(album_id, title)` pairs (no LOWER mangling
  on the call site; the DB does the LOWER).
- `test_int_playlist_falls_through_to_local_path` — integer id routes
  to the existing ownership gate.
- `test_invalid_playlist_id_returns_none` — non-numeric, non-`dz_`
  ids return None so the router 404s.

### Future playlist enhancements

- **Pagination** — Deezer's playlist first page is 25-50 tracks; the
  frontend needs the catalog total (`track_count`) and a `?page=N`/
  `?index=N` query param if the user wants paginated scrolling.
  Phase 6 candidate.
- **Cover lazy-cache** — like Phase 4's artist browse, browse-time
  URLs are raw Deezer CDN; if a track on the playlist is downloaded,
  the parent's cover is local-cached for free by `handle_cover_cache`.
  Bulk local-cover on first browse is a Phase 6 candidate.

---

## Known prefails (not in any phase yet)

- `tests/test_search.py::test_search_returns_404_when_youtube_unavailable` — `logger.log("...")` is mistakenly called in `services/search_service.py:~46`. Should be `logger.info(...)`. Broke during the Phase 0 search migration (introduced there).
- `tests/test_search.py::test_search_excludes_discovered_tracks` — reads `t["video_id"]` after the search migration renamed it to `id`.
- `tests/test_search.py::test_search_local_track_display_artist_fallback` — same `t["video_id"]` KeyError.

These are pre-existing failures in the search migration that happened before this
doc started. Will be fixed as a one-line cleanup pass:

1. `logger.log(...)` → `logger.info(...)` in `services/search_service.py`.
2. Update `t["video_id"]` references to `t["id"]` in `tests/test_search.py`.

Estimated 5 minutes; not blocking Phase 1.

---

## Open questions / Phase 2+ preview

### Phase 2 — Click-time resolution

A user clicking "Download" on a Deezer-sourced track needs a YouTube videoId resolved
on the server via the existing `find_audio_version` helper. Expected surface area:
a new endpoint that accepts the `dz_<int>` track id, server resolves the YT videoId,
persists it as `tracks.id=videoId` + `tracks.album_id='dz_<deezer_album_id>'`,
then enqueues download.

**POLL ONCE PHASE 2 STARTS** — to choose between:

1. New dedicated endpoint `POST /api/tracks/download` (Deezer-shaped body).
2. Or extend existing `POST /favorites/{track_id}` / `POST /playlists/{id}/tracks` to
   accept either a YouTube `videoId` OR a `dz_<int>` and dispatch internally.

### Phase 3+ — Remaining browse endpoints (not yet shipped)

- `GET /api/albums/{dz_album_id}` ✅ **Phase 3 SHIPPED** — reuses the existing
  endpoint via polymorphic dispatch; JSONB-cached tracklist; enriched slim +
  per-track `is_downloaded`/`download_status` + `downloaded_count` aggregate.

- `GET /api/artists/{dz_artist_id}` — **Phase 4 candidate**. Service-layer
  helpers exist (`get_artist_detail`, `get_artist_albums`, `get_artist_top`)
  but no router wiring. Per standing rule "we do not need get artist related
  if it helps us to get other artist than the actual one opened" — keep top +
  albums on the actual artist only; no related-artist fan-out.

- `GET /api/playlists/{dz_playlist_id}` — **Phase 5 candidate**. Service-layer
  helpers exist (`get_playlist_detail`, `get_playlist_tracks`).

- `GET /api/tracks/{dz_track_id}` — **Phase 6 candidate**. Single-track browse
  detail; mirrors `parse_track_detail` slim shape with title-match enrichment.

### Phase 4 — Cover lazy-fetch for browse-time art

Currently browse-time URLs are raw Deezer CDN. `download_deezer_cover(url)` only
fires when invoked by the download worker (Phase 2 click flow). Phase 4 candidates:

- Eagerly cache album/artist/playlist covers on first browse.
- Cache top-song covers along with their parent album.
- Cache the playlist thumbnail at discovery time.

### Phase 5 — Search cache (Postgres-side)

Currently no Postgres-side cache for browsed Deezer metadata. Phase 0 + Phase 1 cache
in-process via the singleton httpx client + `MetadataCache` (existing) — sufficient for
single-session browsing but not multi-user / multi-day. Phase 5 plans a Postgres-side
mirror of parsed Deezer responses, queryable by polymorphic id, so dedicated browse
endpoints don't re-fetch on every page load.

### Misc

- `get_album_detail` first-page `tracks` may diverge from Deezer's reported `nb_tracks`;
  the frontend should prefer to render `len(tracks)` for the visible count, `track_count`
  for the catalog total. Quick fix if the discrepancy becomes annoying.
- `parse_album_track` doesn't carry a `cover_art` because the parent album `cover_url`
  is the canonical image; if your renderer needed per-track cover at deep-zoom levels,
  we can re-add it in a Phase 4 pass.
- `_seed_discovered_tracks` is RETAINED for the legacy YT path. If a future operator
  wants pre-populated Deezer "discovered" rows in the `tracks` table at click-resolve
  time, the simplest extension would be to write a `(title, album_id, position)` row
  inside `TrackService.queue_download`'s Deezer branch (before resolving) so the
  title-match for albums of unclicked tracks has zero ambiguity. Not required for
  Phase 3; flagged for later.
