# Zephyr Backend — API Reference

Complete reference of every HTTP endpoint exposed by the Zephyr backend.

- Base URL: `http://<host>:8000` (configurable via `API_URL`/`settings`).
- All payloads are JSON unless stated otherwise.
- All responses that are images/audio are raw binary (not JSON).

---

## Table of contents

1. [Authentication model](#authentication-model)
2. [Authentication endpoints](#authentication-endpoints)
3. [Search](#search)
4. [Tracks (stream / download / metadata / resolution)](#tracks)
5. [Player (state / multi-device / queue)](#player)
6. [Favorites, Playlists & History](#favorites-playlists--history)
7. [Albums](#albums)
8. [Artists](#artists)
9. [Import (CSV)](#import-csv)
10. [Curator operations](#curator-operations)
11. [Admin management](#admin-management)
12. [SSE events](#sse-events)
13. [Resolution & download contract (status codes)](#resolution--download-contract)

---

## Authentication model

The backend uses a **JWT access token + opaque refresh token** pair, with one DB session row per device (multi-device supported).

| Role | Meaning |
|---|---|
| `user` | Normal, approved user. |
| `curator` | User + content-management powers (`/api/curator/*`). |
| `admin` | Full control (`/api/admin/*` + curator powers). |

**Flow**

1. `POST /api/auth/register` → creates a **pending** user (`is_approved = false`). An admin must approve it.
2. `POST /api/auth/login` → returns `access_token` (short-lived JWT) + `refresh_token` (opaque). Also sets an `access_token` **httpOnly cookie** (`path=/api/tracks`) used by audio/EventSource requests that can't send headers.
3. Send `Authorization: Bearer <access_token>` on every protected request.
4. When the access token expires, call `POST /api/auth/refresh` with `Authorization: Bearer <refresh_token>` to rotate both tokens.

**Notes**

- New accounts are rejected from protected endpoints until approved (and until `must_change_password` is cleared, for the first-boot admin).
- The `access_token` cookie has `path=/api/tracks`, so only the stream/cover/SSE endpoints receive it automatically.

---

## Authentication endpoints

All under prefix `/api/auth`.

### `POST /api/auth/register` — create a user (201)

Body (JSON):

```json
{ "username": "gio", "password": "supersecret123" }
```

Response `201`:

```json
{
  "status": "success",
  "message": "User created successfully, wait for an admin to approve your account"
}
```

Errors: `400` (empty username/password, or username already taken).

---

### `POST /api/auth/login` — authenticate (200)

Form-encoded (`application/x-www-form-urlencoded`, OAuth2 style):

```
username=gatsby&password=supersecret123
```

Response `200`:

```json
{
  "access_token": "<JWT>",
  "refresh_token": "<opaque>",
  "token_type": "bearer",
  "expires_in": 1800,
  "role": "admin",
  "is_approved": true,
  "must_change_password": false
}
```

Errors: `400` (bad credentials). Also sets the `access_token` httpOnly cookie.

---

### `POST /api/auth/refresh` — rotate tokens (200)

Auth: `Authorization: Bearer <refresh_token>` (no access token needed).

Response `200` (same shape as login):

```json
{
  "access_token": "<new JWT>",
  "refresh_token": "<new opaque>",
  "token_type": "bearer",
  "expires_in": 1800,
  "role": "admin",
  "is_approved": true,
  "must_change_password": false
}
```

Errors: `401` (refresh token unknown or grace period expired).

---

### `POST /api/auth/change-password` — change own password (200)

Auth: `Authorization: Bearer <access_token>`.

Body:

```json
{ "current_password": "old", "new_password": "newStrongPass123" }
```

Response `200`:

```json
{
  "status": "success",
  "message": "Password updated. Please log in again.",
  "must_change_password": false
}
```

Errors: `401` (wrong current password), `400` (same password, or weak new password). Revokes all device sessions on success.

---

### `POST /api/auth/logout` — revoke this device's session (204)

Auth: `Authorization: Bearer <refresh_token>`.

Returns `204 No Content` (idempotent). Deletes the calling device's session row.

---

## Search

Prefix `/api/search`.

### `GET /api/search?q=<query>&remote=<bool>` — search music (200)

Auth: `Authorization: Bearer <access_token>`.

Query params:

| Param | Type | Default | Description |
|---|---|---|---|
| `q` | string | *(required)* | Search term. |
| `remote` | bool | `false` | When local results exist, `false` returns local-only; `true` forces a remote (Deezer) fan-out. |

Local-first with a **Deezer fallback**: if the local library has matching tracks/albums/artists/playlists, those are returned (`remote_source: "none"`). Otherwise a remote Deezer search is performed (`remote_source: "deezer"`).

Response `200` (local):

```json
{
  "status": "success",
  "query": "asfalto colla",
  "remote_source": "none",
  "summary": {
    "local_tracks": 1,
    "tracks_count": 0,
    "albums_count": 0,
    "artists_count": 0,
    "playlists_count": 0
  },
  "results": {
    "tracks": [
      {
        "id": "dz_2048189227",
        "title": "Asfalto Colla Zio",
        "artist_name": "TonyPitony",
        "artists_id": "dz_123",
        "album_id": null,
        "cover_art": "/api/tracks/cover/dz_2048189227",
        "is_downloaded": false
      }
    ],
    "albums": [],
    "artists": [],
    "playlists": [],
    "video": []
  }
}
```

Response `200` (remote Deezer):

```json
{
  "status": "success",
  "query": "on the floor",
  "remote_source": "deezer",
  "summary": {
    "local_tracks": 0,
    "tracks_count": 15,
    "albums_count": 0,
    "artists_count": 0,
    "playlists_count": 0
  },
  "results": {
    "tracks": [
      {
        "id": "dz_8930372",
        "title": "On The Floor (Radio Edit)",
        "artist_name": "Jennifer Lopez",
        "artist_id": "dz_123",
        "album_id": "dz_456",
        "album_title": "On The Floor",
        "duration_seconds": 287,
        "cover_art": "https://e-cdns-images.dzcdn.net/images/cover/.../1000x1000-000000-80-0-0.jpg",
        "is_downloaded": false
      }
    ],
    "albums": [],
    "artists": [],
    "playlists": []
  }
}
```

Errors: `400` (empty query), `503` (music service down), `500`.

---

## Tracks

Prefix `/api/tracks`. The `/stream` and `/cover` routes accept auth via the `access_token` cookie (for `<audio>`/`<img>` tags); all others require the `Authorization: Bearer` header.

### `GET /api/tracks/stream/{track_id}` — stream audio (200/206)

Auth: header or cookie.

Streams the track's audio file (with HTTP Range support). If the track is not downloaded yet, it resolves the Deezer/YouTube source, creates the DB row, queues a background download, polls until the file is on disk (≤30s), then streams.

Response:
- `200 OK` — full file (`audio/mpeg`, `audio/mp4`, `audio/flac`, …), `Accept-Ranges: bytes`.
- `206 Partial Content` — ranged request (seeking).

Errors (JSON `detail`):

| Status | Code | Meaning |
|---|---|---|
| `409` | `MATCH_SELECTION_REQUIRED` | Needs manual resolution — see [resolution contract](#resolution--download-contract). |
| `404` | `TRACK_UNAVAILABLE` | No safe YouTube match found. |
| `503` | `PROVIDER_UNAVAILABLE` | Deezer/YouTube temporarily down. |
| `422` | — | Could not resolve the track to a YouTube version. |
| `504` | — | Download still in progress after 30s (retry). |
| `416` | — | Invalid byte range. |

---

### `GET /api/tracks/cover/{track_id}` — cover art (200/302)

Auth: header or cookie.

Returns the album cover for a track. Resolution order: cached file → lazily-fetched CDN image → `302` redirect to the CDN URL. For `dz_<int>` ids with no DB row, the Deezer cover is lazily resolved and a minimal `discovered` row is persisted.

Response: `200` (image/jpeg file) or `302` (redirect). Errors: `404` (no cover source at all).

---

### `GET /api/tracks` — list local tracks (200)

Auth: `Authorization: Bearer`.

Returns all locally downloaded tracks.

```json
{
  "status": "success",
  "count": 42,
  "tracks": [
    {
      "id": "dz_8930372",
      "title": "On The Floor (Radio Edit)",
      "artists": ["Jennifer Lopez"],
      "download_status": "completed",
      "duration": 287
    }
  ]
}
```

---

### `GET /api/tracks/{video_id}` — track metadata (200)

Auth: `Authorization: Bearer`.

Returns full metadata for a track (any download status). `404` if the track has no DB row yet (i.e. it hasn't been streamed/downloaded). **Call this after the track is downloaded** — see the play-flow note in [Resolution & download contract](#resolution--download-contract).

```json
{
  "track_id": "dz_8930372",
  "video_id": "dz_8930372",
  "yt_id": "dQw4w9WgXcQ",
  "title": "On The Floor (Radio Edit)",
  "artists": ["Jennifer Lopez"],
  "album": "On The Floor",
  "duration_seconds": 287,
  "download_status": "completed",
  "has_lyrics": true,
  "lyrics_text": "Let me introduce you to my party people...",
  "lyrics_lrc": "[00:00.00] ...",
  "stream_url": "/api/tracks/stream/dz_8930372",
  "cover_url": "/api/tracks/cover/dz_8930372"
}
```

---

### `GET /api/tracks/{track_id}/album` — track → album lookup (200)

Auth: `Authorization: Bearer`.

```json
{ "album_id": "dz_123", "album_name": "On The Floor", "source": "local" }
```

`source` is `"local"` (DB `album_id`) or `"remote"` (YouTube fallback). Errors: `404`, `503`.

---

### `GET /api/tracks/{track_id}/discovery?limit=15` — radio queue (200)

Auth: `Authorization: Bearer`.

Composes a Deezer-only radio queue from a seed track (tiers: 1 album sibling → ≤2 same-artist → similar artists). `limit` 1–50.

```json
{
  "seed": "dz_8930372",
  "reason": null,
  "queue": [
    {
      "track_id": "dz_123456",
      "title": "Some Related Song",
      "artists": ["Someone"],
      "album": "Album Title",
      "duration_seconds": 210,
      "cover_url": "/api/tracks/cover/dz_123456",
      "stream_url": "/api/tracks/stream/dz_123456",
      "reason": "same_artist"
    }
  ]
}
```

A seed without a Deezer identity returns `{ "seed": "...", "reason": "seed_without_deezer_identity", "queue": [] }`.

---

### `GET /api/tracks/{video_id}/related` — related content (200)

Auth: `Authorization: Bearer`.

YouTube Music "Related" tab content.

```json
{
  "video_id": "dQw4w9WgXcQ",
  "sections": [
    { "title": "You might also like", "contents": [ { ... } ] }
  ]
}
```

Errors: `404`, `500`.

---

### Resolution endpoints

#### `GET /api/tracks/{track_id}/resolution` — current resolution request (200)

Auth: `Authorization: Bearer`.

Returns the active resolution request (`find_active_for_track`), including `candidates` (each: `video_id`, `title`, `artists`, `duration_seconds`, `video_type`, `thumbnail`). `404` if none.

#### `POST /api/tracks/{track_id}/resolution` — select a candidate (202)

Auth: `Authorization: Bearer`.

Body:

```json
{ "resolution_id": "…", "video_id": "dQw4w9WgXcQ" }
```

Response `202`:

```json
{
  "status": "queued",
  "track_id": "dz_8930372",
  "video_id": "dz_8930372",
  "yt_id": "dQw4w9WgXcQ",
  "title": "On The Floor (Radio Edit)",
  "stream_url": "/api/tracks/stream/dz_8930372",
  "resolution_id": "…"
}
```

Errors: `422` `{ "code": "INVALID_RESOLUTION", "message": "..." }`.

#### `POST /api/tracks/{track_id}/resolution/search?q=<query>` — custom search (200)

Auth: `Authorization: Bearer`.

Runs a user-typed YouTube search, stores the results as candidates. Only valid for tracks in `unavailable`/`needs_resolution`.

Response `200`:

```json
{
  "status": "needs_resolution",
  "track_id": "dz_8930372",
  "resolution_id": "…",
  "candidates": [
    {
      "video_id": "dQw4w9WgXcQ",
      "title": "On The Floor",
      "artists": ["Jennifer Lopez"],
      "duration_seconds": 287,
      "video_type": "ATV",
      "thumbnail": "https://…"
    }
  ]
}
```

Errors: `404`, `422` `{ "code": "CUSTOM_SEARCH_INVALID", ... }`, `503`.

#### `DELETE /api/tracks/{track_id}/resolution?resolution_id=<id>` — cancel (204)

Auth: `Authorization: Bearer`. Cancels an owned resolution request. Returns `204`; `404` if not found.

#### `POST /api/tracks/{track_id}/resolution/reopen` — reopen (200)

Auth: `Authorization: Bearer`. "Report wrong match": clears the assigned YouTube source, deletes local audio/lyrics files, sets `needs_resolution`, flags `skip_automatch` (background worker can't re-claim), and pre-populates the modal with a fresh search.

```json
{ "status": "needs_resolution", "track_id": "dz_8930372", "request": { ... } }
```

Errors: `403` (owned by another user), `404`, `409`, `422`, `503`.

---

### `POST /api/tracks/download/{track_id}` — queue a download (202)

Auth: `Authorization: Bearer`.

Accepts a `video_id` or a `dz_<int>` id. Resolves the source, creates/updates the DB row, and starts a background download. Returns immediately.

Response `202` (queued):

```json
{
  "status": "queued",
  "track_id": "dz_8930372",
  "video_id": "dz_8930372",
  "yt_id": "dQw4w9WgXcQ",
  "title": "On The Floor (Radio Edit)",
  "message": "Download queued. YouTube download takes < 1 second.",
  "stream_url": "/api/tracks/stream/dz_8930372"
}
```

If already downloaded, `status` is `"success"` with `"message": "Track is already available locally"`.

Errors: `409` `MATCH_SELECTION_REQUIRED`, `404` `TRACK_UNAVAILABLE`, `422`, `503`, `500`.

---

## Player

Prefix `/api/player`. Auth: `Authorization: Bearer` (the SSE endpoint also accepts the cookie).

### `GET /api/player/state?device_id=<id>` — current state (200)

Returns the full playback state, refilling the radio queue when it runs low. Pass `device_id` to get the `is_player` flag back.

```json
{
  "device_id": "uuid-of-owner",
  "device_name": "Gio's Laptop",
  "current_track_id": "dz_8930372",
  "position_ms": 83000,
  "is_playing": true,
  "queue": [
    {
      "track_id": "dz_123456",
      "title": "…",
      "artists": ["…"],
      "album": "…",
      "duration_seconds": 210,
      "cover_url": "/api/tracks/cover/dz_123456",
      "stream_url": "/api/tracks/stream/dz_123456",
      "reason": "similar_artist"
    }
  ],
  "queue_count": 15,
  "queue_mode": "radio",
  "history": [ { "track_id": "dz_…", "source": "queue" } ],
  "history_count": 3,
  "user_queue": [],
  "user_queue_count": 0,
  "player_heartbeat_at": "2026-08-14T12:00:00",
  "updated_at": "2026-08-14T12:00:01",
  "is_player": true,
  "refilled": false
}
```

---

### `PUT /api/player/state` — heartbeat / track change (200)

Auth: `Authorization: Bearer`. Body (all fields optional — only provided fields overwrite):

```json
{
  "device_id": "uuid-of-device",
  "device_name": "Gio's Laptop",
  "current_track_id": "dz_8930372",
  "position_ms": 12000,
  "is_playing": true,
  "queue_mode": "radio",
  "queue": [],
  "origin": "queue"
}
```

Semantics:

- With `device_id` → **ownership write** (claim when free, heartbeat when owner, `409 PLAYER_ACTIVE` when a live owner differs).
- Without `device_id` → **remote intent** (fields apply, ownership unchanged).
- `queue_mode` (`radio` | `context`) + `queue` load a frontend-owned queue (playlist/favorites/album); `context` mode disables discovery injection.
- `origin` (`queue` | `context`): a `queue` click skips the queue to that track; a `context` click plays it now and removes only it.

Returns the serialized state (same shape as `GET /state`).

Errors: `409` `{ "code": "PLAYER_ACTIVE", "device_id": "…", "device_name": "…" }`, `422`.

---

### `GET /api/player/devices` — connected devices (200)

The "connect to a device" picker: every device with a live SSE connection plus the session owner.

```json
{
  "devices": [
    { "device_id": "uuid", "device_name": "Gio's Laptop", "is_player": true, "is_alive": true },
    { "device_id": "uuid2", "device_name": "Gio's Phone", "is_player": false, "is_alive": true }
  ]
}
```

---

### `GET /api/player/queue` — queue only (200)

```json
{
  "queue": [ { "track_id": "…", "title": "…", "artists": ["…"], "stream_url": "/api/tracks/stream/…", "cover_url": "…", "reason": "…" } ],
  "queue_count": 15,
  "user_queue": [],
  "user_queue_count": 0
}
```

---

### `GET /api/player/events` — SSE stream

Auth: cookie (EventSource can't send headers). Query params: `device_id`, `device_name` (optional label).

Server-Sent Events stream. Events:

- `event: state` → full state snapshot on connect + on every mutation.
- `event: library` → favorites/playlists/history changes (see [SSE events](#sse-events)).
- `event: track_status` → download completion (see [SSE events](#sse-events)).
- `event: devices` → device list changed.
- `: ping` comment every ~20s (keep-alive). `retry: 3000` on connect.

---

### `POST /api/player/command` — remote-control intent (200)

Auth: `Authorization: Bearer`. Body:

```json
{ "action": "play_track", "current_track_id": "dz_8930372", "position_ms": 0, "origin": "queue" }
```

`action` ∈ `"play_track" | "pause" | "toggle" | "seek"`. Ownership never changes — the backend applies the intent and pushes state; the **owner** device executes it. `422` on unknown action.

---

### `POST /api/player/takeover` — become the player (200)

Auth: `Authorization: Bearer`. Body:

```json
{ "device_id": "uuid", "device_name": "Gio's Phone", "force": true }
```

`409 PLAYER_ACTIVE` while a live owner differs; resend with `force: true` after user confirmation. Returns the serialized state.

---

### `POST /api/player/next` — next track (200)

Auth: `Authorization: Bearer`. Advances (user queue drains first). Returns the serialized state. `404` if nothing queued.

---

### `POST /api/player/previous` — previous track (200)

Auth: `Authorization: Bearer`. Steps back one track (restores it at 0:00 and re-inserts the skipped track at the head of its queue). `404` if history is empty.

---

### `POST /api/player/user-queue` — add to user queue (200)

Auth: `Authorization: Bearer`. Body (the same item shape used for queue entries):

```json
{ "track": { "track_id": "dz_…", "title": "…", "artists": ["…"], "album": "…", "duration_seconds": 210, "cover_url": "…", "stream_url": "/api/tracks/stream/…" } }
```

Spotify-style "add to queue": plays before the radio/context queue. Returns the serialized state.

---

### `DELETE /api/player/user-queue` — clear user queue (200)

Auth: `Authorization: Bearer`. Empties the user queue. Returns the serialized state.

---

## Favorites, Playlists & History

Prefix `/api`. Auth: `Authorization: Bearer`.

### Favorites

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/favorites?offset=0` | User's favourites (ordered by favourited_at desc). |
| `GET` | `/api/favorites/{track_id}` | `{ "is_favorite": true }` |
| `POST` | `/api/favorites/{track_id}` | Add to favourites (auto-downloads if missing). `201` → `{ "favorite_id": "…" }` |
| `DELETE` | `/api/favorites/{track_id}` | Remove. `{ "favorite_id": "…" }` |

`POST` errors mirror the resolution contract: `409 MATCH_SELECTION_REQUIRED`, `404`, `422`, `503`.

---

### Playlists

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/playlists` | List user's playlists. |
| `GET` | `/api/playlists/{id}` | Playlist detail + tracks. `dz_<int>` ids → Deezer browse; int ids → local. Owner always; non-owners only if public. |
| `POST` | `/api/playlists` | Create. Body `{ "name": "…", "description": "", "is_public": false }` → `201 { "playlist_id": 5, "name": "…" }`. |
| `PUT` | `/api/playlists/{id}` | Update (owner). Body `{ "name"?, "description"?, "is_public"? }` → `{ "status": "updated" }`. |
| `DELETE` | `/api/playlists/{id}` | Delete (owner) → `{ "status": "deleted" }`. |
| `POST` | `/api/playlists/{id}/cover` | Upload cover (owner, multipart `file`) → `{ "cover_url": "/api/playlists/{id}/cover" }`. |
| `GET` | `/api/playlists/{id}/cover` | Serve cover image (owner/public). `404` if none uploaded. |
| `POST` | `/api/playlists/{id}/tracks` | Add track (owner, auto-downloads). Body `{ "track_id": "dz_…" }` → `201 { "status": "added", "track_id": "…" }`. |
| `DELETE` | `/api/playlists/{id}/tracks` | Remove track (owner). Body `{ "track_id": "…" }` → `{ "status": "removed", "track_id": "…" }`. |
| `PUT` | `/api/playlists/{id}/tracks/reorder` | Reorder (owner). Body `{ "new_order": ["id1","id2",…] }` → `{ "status": "reordered", "new_order": [...] }`. |
| `GET` | `/api/playlists/{id}/tracks` | Tracks list (ownership-aware). |

---

### History

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/history` | Record a listen. Body `{ "track_id": "dz_…" }` → `201 { "status": "recorded", "track_id": "…" }`. |
| `GET` | `/api/history` | `{ "records": [ … ] }` |
| `GET` | `/api/history/statistics?period=all` | Aggregated stats. `period` ∈ `1m` (30d), `6m` (180d), `1y` (365d), `all`. `400` on bad period. |

---

## Albums

Prefix `/api`. Auth: `Authorization: Bearer`.

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/albums/local` | Curator-created albums (`local_album_*`). `{ "status": "success", "count": N, "albums": [...] }`. |
| `GET` | `/api/albums/{album_id}?refresh=false` | Album detail + per-track download status. `dz_<int>` → Deezer; `MPREb_…`/`local_album_*` → YT/curator cache. |
| `POST` | `/api/albums/download/{album_id}` | Download all album tracks (background). `202` with queued/already-downloaded counts. |
| `GET` | `/api/albums/cover/{album_id}` | Serve album cover (curator override → cached → lazy CDN fetch). |

`POST /download` response `202`:

```json
{
  "album": "On The Floor",
  "artists": ["Jennifer Lopez"],
  "total_tracks": 10,
  "queued_for_download": 8,
  "already_downloaded": 2,
  "needs_resolution": 0,
  "unavailable": 0,
  "failed": 0
}
```

---

## Artists

Prefix `/api`. Auth: `Authorization: Bearer`.

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/artists/local` | Curator-created artists. `{ "status": "success", "count": N, "artists": [...] }`. |
| `GET` | `/api/artists/by-name/{name}` | Case-insensitive name lookup. `{ "status": "success", "query": "…", "count": N, "artists": [{ "id", "name", "is_local" }] }`. |
| `GET` | `/api/artists/directory?limit=50&offset=0` | Paginated unified directory (YT + curator). |
| `GET` | `/api/artists/cover/{artist_id}` | Serve artist photo (file → CDN redirect → lazy Deezer fetch). |
| `GET` | `/api/artists/{channel_id}` | Artist detail. `dz_<int>` → Deezer; `UC…`/`local_artist_*` → YT/local. |
| `GET` | `/api/artists/local/{artist_id}` | Local artist detail + its library tracks. |

---

## Import (CSV)

Prefix `/api/import`. Auth: `Authorization: Bearer`.

### `POST /api/import/csv` — start import (202)

Multipart `file` (Spotify Exportify CSV). Required columns: `Track Name`, `Artist Name(s)` (+ optional `Duration (ms)`). Max 2000 rows.

Response `202`:

```json
{ "job_id": "…", "status": "queued" }
```

Routing: `Liked_Songs.csv` → favourites; any other filename → a private playlist named after the file. Errors: `400` (bad CSV/too many rows), `503`.

---

### `GET /api/import/status/{job_id}` — poll progress (200)

```json
{
  "job_id": "…",
  "status": "processing",
  "total": 100,
  "processed": 40,
  "queued": 35,
  "failed": 2,
  "needs_review": 3,
  "unavailable": 2,
  "failed_tracks": [ { "title": "…", "reason": "…" } ],
  "review_items": [
    {
      "id": "…",
      "track_id": "…",
      "source_title": "…",
      "source_artists": ["…"],
      "reason_code": "MATCH_SELECTION_REQUIRED",
      "candidates": [ { "video_id": "…", "title": "…", "artists": ["…"], "duration_seconds": 200, "video_type": "ATV", "thumbnail": "…" } ]
    }
  ]
}
```

---

### `POST /api/import/resolution/{resolution_id}` — select import candidate (202)

Body `{ "candidate_id": "…" }` (the `video_id`). Continues that row. `422` on error.

### `POST /api/import/resolution/{resolution_id}/retry` — retry provider lookup (202)

Retries the failed Deezer/YouTube lookup for an import row.

---

## Curator operations

Prefix `/api/curator`. Auth: `Authorization: Bearer` + role `curator` (or `admin`) + rotated password.

| Method | Path | Description |
|---|---|---|
| `PUT` | `/api/curator/tracks/{track_id}` | Partially update metadata. Body `{ "title"?, "artist_ids"?, "album_id"?, "lyrics"?, "lyrics_lrc"? }` → `{ "status": "updated", "track_id": "…" }`. `400` with `missing_ids` if an artist id is unknown. |
| `POST` | `/api/curator/tracks/{track_id}/cover` | Replace track cover (multipart image). → `{ "status": "updated", "track_id", "cover_path" }`. |
| `POST` | `/api/curator/albums` | Create local album. Body `{ "title", "artist_ids", "year"?, "track_ids" }` → `201 { "status": "created", "id": "local_album_…", "track_count", "skipped_track_ids", "album_url" }`. |
| `POST` | `/api/curator/albums/{album_id}/cover` | Upload album cover (multipart image) → `{ "status": "updated", "id", "cover_url" }`. |
| `POST` | `/api/curator/artists` | Create local artist. Body `{ "name", "bio" }` → `201 { "status": "created", "artist_id": "local_artist_…", "name", "artist_url" }`. `409` on duplicate name. |
| `POST` | `/api/curator/artists/{artist_id}/cover` | Upload artist photo (multipart image). |
| `POST` | `/api/curator/tracks/upload` | Upload a local audio file (see below). |

### `POST /api/curator/tracks/upload` — upload audio (201)

Multipart form fields: `file` (audio), `title`, `artists` (comma-separated), `album` (optional), `target_track_id` (optional).

- Without `target_track_id` → mints `local_{uuid12}` id, marks `completed`, extracts duration.
- With `target_track_id` → binds the file to an existing `unavailable`/`needs_resolution`/`discovered` track (fulfills it; `is_local_upload = true`).

Response `201`:

```json
{
  "status": "created",
  "track_id": "local_ab12cd34ef56",
  "title": "My Song",
  "artists": ["Me"],
  "album": "My Album",
  "duration": 190,
  "stream_url": "/api/tracks/stream/local_ab12cd34ef56",
  "metadata_url": "/api/tracks/local_ab12cd34ef56"
}
```

Errors: `400` (unsupported type / unreadable audio), `404` (target not found), `409` (state conflict).

---

## Admin management

Prefix `/api/admin`. Auth: `Authorization: Bearer` + role `admin` + rotated password.

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/admin/users/pending` | `{ "status": "success", "pending_users": [...] }`. |
| `GET` | `/api/admin/users` | `{ "status": "success", "users": [...] }`. |
| `POST` | `/api/admin/users/{username}/approve` | `{ "status": "success", "message": "Admin approved the user: …" }`. |
| `POST` | `/api/admin/curator/{username}` | Promote to curator. |
| `GET` | `/api/admin/stats` | `{ "status": "success", "stats": {...} }` (tracks per status, disk usage, users). |
| `GET` | `/api/admin/orphans` | `{ "status": "success", "orphans": { "records_without_file": [...], "files_without_record": [...] } }`. |
| `POST` | `/api/admin/retry-failed` | Reset all `failed` tracks → `{ "status": "success", "retried_count": N }`. |
| `DELETE` | `/api/admin/tracks/{track_id}` | Delete a track + its files → `{ "status": "success", "message": "Track … deleted successfully" }`. |
| `GET` | `/api/admin/youtube-cookies` | Cookie file state (names only, never values). |
| `POST` | `/api/admin/youtube-cookies` | Upload a fresh `cookies.txt` (validated, atomic). |

### `GET /api/admin/youtube-cookies` (200)

```json
{
  "status": "success",
  "cookies": {
    "path": "/app/youtube_cookies.txt",
    "exists": true,
    "size_bytes": 6142,
    "modified_at": "2026-08-14 12:05:00",
    "present": ["SAPISID", "SID", "HSID", "__Secure-1PSID"],
    "missing": []
  }
}
```

### `POST /api/admin/youtube-cookies` (200)

Multipart `file`. On success:

```json
{
  "status": "success",
  "message": "YouTube cookies updated — effective immediately",
  "path": "/app/youtube_cookies.txt",
  "cookies": { "exists": true, "present": ["SAPISID","SID","HSID","__Secure-1PSID"], "missing": [], "size_bytes": 6142, "modified_at": "…", "path": "/app/youtube_cookies.txt" }
}
```

Errors: `422` `{ "detail": { "code": "INVALID_COOKIES", "message": "…", "missing": ["SAPISID"] } }`, `413` (over 1MB).

---

## SSE events

All events arrive on `GET /api/player/events`. Each frame is `event: <name>\ndata: <json>\n\n`.

| Event | Payload | Meaning |
|---|---|---|
| `state` | full state snapshot | Player state changed (track, play/pause, position, queue). |
| `library` | `{ "scope": "favorites"\|"playlists"\|"history", "action": "added"\|"removed"\|"created"\|"updated"\|"deleted"\|"reordered", "track_id"?, "playlist_id"? }` | A library mutation happened (per-user broadcast). |
| `track_status` | `{ "track_id": "dz_123", "download_status": "completed"\|"failed" }` | A download reached a terminal state (global broadcast). |
| `devices` | device list | A device connected/disconnected (refresh the picker). |

---

## Resolution & download contract

The canonical track lifecycle for a not-yet-downloaded track:

```
render-from-payload → GET /api/tracks/stream/{id} (or POST /download/{id})
   ├─ 409 MATCH_SELECTION_REQUIRED → show candidate modal
   │     POST /api/tracks/{id}/resolution            (select candidate)
   │     POST /api/tracks/{id}/resolution/search      (custom search)
   │     POST /api/tracks/{id}/resolution/reopen      (report wrong match)
   ├─ 404 TRACK_UNAVAILABLE        → unavailable state
   ├─ 503 PROVIDER_UNAVAILABLE     → retry later
   ├─ 504 (still downloading)      → wait/retry
   └─ 200/206 → audio
then: SSE `track_status: completed` → GET /api/tracks/{id} (metadata/lyrics)
```

**409 candidate payload** (`MATCH_SELECTION_REQUIRED`):

```json
{
  "code": "MATCH_SELECTION_REQUIRED",
  "track_id": "dz_8930372",
  "resolution_id": "…",
  "title": "On The Floor (Radio Edit)",
  "artists": ["Jennifer Lopez"],
  "duration_seconds": 287,
  "candidates": [
    {
      "video_id": "dQw4w9WgXcQ",
      "title": "On The Floor",
      "artists": ["Jennifer Lopez"],
      "duration_seconds": 287,
      "video_type": "ATV",
      "thumbnail": "https://…"
    }
  ]
}
```

**Important client rules**

- `GET /api/tracks/{id}` returns `404` for a track with no DB row yet. It is a **post-download metadata** call, not the "start playing" call — render from the search/queue payload first, stream, then fetch metadata on `track_status: completed`.
- Only the **owner device** (`device_id == state.device_id`) calls `GET /api/tracks/stream/{id}`. Remote devices only send `POST /api/player/command` and mirror state from SSE.
