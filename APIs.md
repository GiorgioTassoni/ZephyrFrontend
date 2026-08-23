# Zephyr Music — Backend API Reference

> Base URL: `https://<your-domain>/api`

All authenticated endpoints require `Authorization: Bearer <access_token>` unless noted otherwise. Tokens are obtained via `/api/auth/login` and refreshed via `/api/auth/refresh`.

---

## Table of Contents

1. [Authentication](#1-authentication)
2. [Player](#2-player)
3. [Tracks](#3-tracks)
4. [Search](#4-search)
5. [Playlists & Favorites](#5-playlists--favorites)
6. [Albums](#6-albums)
7. [Artists](#7-artists)
8. [Import](#8-import)
9. [Curator](#9-curator)
10. [Admin](#10-admin)
11. [Health](#11-health)

---

## 1. Authentication

### `POST /api/auth/register`

Register a new user. Account requires admin approval before login.

**Request Body:**
```json
{
  "username": "string",
  "password": "string"
}
```

**Response `201 Created`:**
```json
{
  "status": "success",
  "message": "User created successfully, wait for an admin to approve your account"
}
```

**Errors:**
- `400` — Bad username or password / User already exists

---

### `POST /api/auth/login`

Authenticate and receive a token pair.

**Request:** `application/x-www-form-urlencoded`
| Field | Type | Required |
|---|---|---|
| `username` | string | yes |
| `password` | string | yes |

**Response `200 OK`:**
```json
{
  "access_token": "eyJ...",
  "refresh_token": "opaque_string",
  "token_type": "bearer",
  "expires_in": 900,
  "role": "user",
  "is_approved": true,
  "must_change_password": false
}
```

**Token lifetimes:**
- `access_token`: 15 minutes (JWT, used for Authorization headers)
- `refresh_token`: 14 days (opaque, used only by `/refresh`). Slides on each refresh — active users stay logged in indefinitely.

**Errors:**
- `400` — Bad username or password

---

### `POST /api/auth/refresh`

Rotate the refresh token and issue a new token pair. **No access token required** — the refresh token itself is the proof of identity.

**Request:** `Authorization: Bearer <refresh_token>`

**Response `200 OK`:**
```json
{
  "access_token": "eyJ...",
  "refresh_token": "new_opaque_string",
  "token_type": "bearer",
  "expires_in": 900,
  "role": "user",
  "is_approved": true,
  "must_change_password": false
}
```

**Errors:**
- `401` — Refresh token invalid or expired

---

### `POST /api/auth/change-password`

Change the authenticated user's password. All device sessions are revoked on success — re-login required.

**Request Body:**
```json
{
  "current_password": "string",
  "new_password": "string"
}
```

**Response `200 OK`:**
```json
{
  "status": "success",
  "message": "Password updated. Please log in again.",
  "must_change_password": false
}
```

**Errors:**
- `401` — Current password incorrect
- `400` — New password same as current / fails strength check

---

### `POST /api/auth/logout`

End the calling device's session (other devices stay logged in).

**Request:** `Authorization: Bearer <refresh_token>`

**Response `204 No Content`**

---

## 2. Player

### `GET /api/player/state`

Get the current playback state + queue for the user's session.

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `device_id` | string (optional) | Caller's device ID — returns `is_player` flag in response |

**Response `200 OK`:**
```json
{
  "device_id": "flutter_abc",
  "current_track_id": "dz_123",
  "position_ms": 42000,
  "is_playing": true,
  "queue": [...],
  "queue_count": 15,
  "queue_mode": "radio",
  "history": [{"track_id": "dz_prev", "source": "queue"}],
  "history_count": 1,
  "user_queue": [...],
  "user_queue_count": 2,
  "player_heartbeat_at": "2026-08-20T10:52:00Z",
  "position_updated_at": "2026-08-20T10:52:00Z",
  "updated_at": "2026-08-20T10:52:00Z",
  "is_player": true,
  "refilled": false,
  "radio_status": "ready",           // "idle" | "pending" | "ready" | "failed"
  "radio_request_id": "a1b2c3...",  // unique id of the current radio generation
  "radio_generation": 3,             // monotonic counter, bumps on every seed
  "radio_error": {},                 // {code, message} when radio_status == "failed"
  "context_ref": {                   // null when no server-resolved context is active
    "type": "playlist",             // "playlist" | "album" | "favorites"
    "id": "pl_42",                  // omitted for favorites
    "order": "as_listed",           // "as_listed" | "shuffled"
    "offset": 0
  },
  "context_order_active": "linear", // "linear" | "shuffled" | null (the toggled order the cursor walks)
  "context_cursor": 0,               // position in the active order (0 = first remaining)
  "context_total": 500,              // full remaining context size (all unplayed tracks)
  "context_status": "ready",        // "idle" | "pending" | "ready" | "failed"
  "context_request_id": null,        // stale-result guard for async resolution
  "context_error": {},               // {code, message} when context_status == "failed"
  "_sse_initial": false
}
```

**Notes:**
- All timestamps are UTC ISO-8601 with explicit `Z` suffix.
- `_sse_initial: true` marks the snapshot sent on SSE connect/reconnect.
- Queue modes: `radio` (server-managed, auto-refilled) or `context` (frontend-managed, no discovery).
- **Radio generation is async (Exchange 59).** `radio_status` tells the client what the queue means: `pending` → generation in flight, `queue` is empty by design (keep playing the current track, the ready event arrives via SSE); `ready` → queue is the generated radio; `failed` → generation died (`radio_error` has the `{code, message}`), the queue is permanently empty until the user re-seeds. `radio_request_id` / `radio_generation` let a reconnecting client correlate the state with the in-flight/committed job. A `pending` row whose job was lost (server restart) is lazily failed with `code: "radio_job_lost"` on the next read.

---

### `PUT /api/player/state`

Apply a heartbeat / track change. Partial — only provided fields overwrite.

**Request Body:**
```json
{
  "device_id": "flutter_abc",          // optional: ownership write (claim/heartbeat)
  "device_name": "Gio's iPhone",       // optional: device label
  "current_track_id": "dz_123",        // optional: new track
  "position_ms": 42000,                // optional: cursor position
  "is_playing": true,                  // optional: play/pause
  "queue_mode": "radio",              // optional: "radio" | "context"
  "queue": [...],                      // optional: frontend-owned queue (context mode)
  "context_ref": {                     // optional (Exchange 60): server-resolved context
    "type": "playlist",              //   "playlist" | "album" | "favorites"
    "id": "pl_42",                   //   omitted for favorites (implicit per-user)
    "order": "as_listed",            //   "as_listed" | "shuffled"
    "offset": 17                      //   optional: start index into the resolved list
  },
  "origin": "queue",                  // optional: "queue" | "context"
  "seed_radio": true                   // optional: start a fresh radio queue
}
```

**Ownership rules:**
- **With `device_id`**: ownership write — claim when free, heartbeat when owner, `409 PLAYER_ACTIVE` when a live owner differs.
- **Without `device_id`**: remote command — fields apply, ownership unchanged.

**`origin` semantics:**
- `"queue"` — skip to that track in the queue view (drop everything before it, keep the rest).
- `"context"` — play it now and remove just it from the queue.
- absent — legacy head-drain rules (queue respected, nothing regenerates).

> **When a server-resolved `context_ref` is active**, both `"queue"` and `"context"` clicks are treated as click-to-play within the context — the **active order** decides the exact semantics (`linear` → skip-to, `shuffled` → play-now-remove-one). See the `context_ref` section below; the plain-queue rules above only apply to ad-hoc `queue: [...]` contexts.

**`seed_radio` semantics (the ONLY fresh-radio trigger) — async (Exchange 59):**
- `true` + `current_track_id` — atomically discard the normal queue, consume the track from the user queue if present, reset history, stamp `radio_status: "pending"` with a fresh `radio_request_id` + bumped `radio_generation`, spawn a background generation job, and **return immediately** (the request no longer blocks on Deezer discovery). Implies `queue_mode: "radio"` (flips the session even from a context queue).
- `false` / absent — the queue is fully respected: advance, skip and head-pops never regenerate it.
- `true` without `current_track_id` — `422` (nothing to seed from).
- Send it on **search-result plays** and "Play Radio" actions. Never on advance/skip — those use `POST /api/player/next` and respect the queue.

**Immediate response:** `200 OK` with the full player state, `queue: []`, `queue_count: 0`, `radio_status: "pending"`, `radio_request_id` (a unique id), `radio_generation`, `updated_at`. Start playback of `current_track_id` right away — the queue is only needed for what plays next.

**Background job:** runs discovery with bounded retries (3 attempts, short backoff, 60s hard deadline), dedupes, excludes the seed track, caps at 15. It commits the queue **only if `radio_request_id` is still current** — a newer seed, a context queue load, or a queue-view/playlist skip replaces the id, so a slow old job's result is discarded (`radio_seed_job_discarded_stale`). On success it broadcasts a normal SSE `state` event with `radio_status: "ready"`, the seeded `queue` and the same `radio_request_id`. On permanent failure (provider down after retries, `empty_discovery`, `seed_without_deezer_identity`) it broadcasts `radio_status: "failed"` + `radio_error: {code, message}` and persists the failed state for reconnecting clients.

**`queue_mode` + `queue`:** Load a frontend-owned context queue (playlist/favorites/album). In `context` mode the backend never injects discovery tracks. Ignored when `seed_radio: true` (the seed wins). Loading a queue also supersedes any in-flight radio generation.

**`context_ref` — server-resolved context queue (Exchange 60):** Instead of uploading a full `queue: [...]` array for a known collection, send a lightweight reference and the server resolves / shuffles / walks the list for you.
- **Mutually exclusive with `queue`** — sending both returns `422`.
- **Resolution:** the server resolves the track IDs once (local playlists / albums / favorites are a single indexed query; Deezer `dz_` playlists are paginated), builds **both** a `linear` and a `shuffled` order, and stores them in the session row. `order` picks which one is active; `offset` (optional) starts the cursor there.
- **Derived `queue`:** the response's `queue` is the *display window* — `active_order[cursor : cursor+50]`, hydrated back into full track dicts — while `queue_count` is the **real remaining** count (`context_total = active_order.length`). Both orders always only contain *unplayed* tracks: advancing dual-pops the played track off both, so toggling linear↔shuffled never replays anything.
- **Skip (`POST /api/player/next`)**: cursor walk over the active order (O(1)) — no discovery, no re-resolution. `previous` re-inserts the skipped track. No `404` until the context is genuinely exhausted.
- **Click-to-play (a specific track):** send `current_track_id` + `origin` (`"context"` for playlist-page clicks, `"queue"` for queue-view clicks) and the server applies the **active-order rule** — never leaving the cursor stale:
  - **`linear` active → skip-to**: all remaining tracks from the cursor up to *and including* the clicked one are dropped from **both** orders and the cursor resets to 0, so `next` continues with the track **after** the clicked one. *(Click #32 while on #3 → plays #32, then #33 → #34 → ….)*
  - **`shuffled` active → play-now-remove-one**: only the clicked track is removed (pulled out of **both** orders so it is never replayed); the rest of the shuffled **unplayed** set keeps playing in order — no arbitrary prefix is dropped in a randomized list.
- **Toggle / re-shuffle:** `POST /api/player/context/toggle` flips linear↔shuffled (cursor resets to 0); `POST /api/player/context/reshuffle` regenerates the shuffled order from what remains. See below.
- **`seed_radio: true`** replaces any active context wholesale (radio wins).

**Response:** Full player state (same shape as `GET /api/player/state`).

**Errors:**
- `409` — `PLAYER_ACTIVE` (another device owns the session)
- `422` — `seed_radio` without `current_track_id`, or `context_ref` together with `queue`

---

### `GET /api/player/queue`

Get the radio queue (refilled server-side when low) plus the higher-priority user queue.

**Response `200 OK`:**
```json
{
  "queue": [...],
  "queue_count": 15,
  "user_queue": [...],
  "user_queue_count": 2
}
```

---

### `GET /api/player/devices`

List every device with a live SSE connection, plus the session owner — the "connect to a device" picker.

**Response `200 OK`:**
```json
[
  { "device_id": "flutter_abc", "device_name": "Gio's iPhone", "is_player": true, "is_alive": true },
  { "device_id": "web_123", "device_name": "Chrome", "is_player": false, "is_alive": true }
]
```

---

### `GET /api/player/events`

Server-Sent Events stream for live multi-device sync. Auth via cookie fallback (EventSource cannot send Authorization headers).

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `device_id` | string | Your device ID — marks you as alive even with stale heartbeat |
| `device_name` | string (optional) | Human label for `GET /devices` |

**Events received:**
- `state` — Full player state snapshot (on connect + every mutation)
- `sse_closed` — Connection kicked (per-user limit exceeded)
- `: ping` — Keep-alive every ~20s

**Headers:**
```
retry: 3000
```

---

### `POST /api/player/command`

Remote-control intent from any device. Never changes ownership — the owner's device executes the action.

**Request Body:**
```json
{
  "action": "play_track",          // "play_track" | "pause" | "toggle" | "seek" | "next" | "previous"
  "current_track_id": "dz_123",   // required for play_track
  "position_ms": 42000,           // required for seek
  "origin": "queue",              // optional: "queue" | "context"
  "seed_radio": true               // optional (play_track): fresh radio queue
}
```

**`action` semantics:**
- `play_track` — play a track (ownership unchanged); `origin` / `seed_radio` apply
- `pause` / `toggle` / `seek` — control the owner's playback
- `next` — advance to the next track (same as `POST /api/player/next`)
- `previous` — step back one track (same as `POST /api/player/previous`)

**Response:** Full player state.

**Errors:**
- `422` — Invalid action / missing required field
- `202` — `next` while a radio generation is still `pending` and both queues are empty (body is the full state with `radio_status: "pending"` — keep playing the current track, the queue arrives via SSE)
- `404` — `next` with an empty queue, or `previous` with no history

---

### `POST /api/player/takeover`

Explicitly become the player ("Play here"). Returns `409` while a live owner differs; resend with `force: true` after user confirmation.

**Request Body:**
```json
{
  "device_id": "flutter_abc",
  "device_name": "Gio's iPhone",   // optional
  "force": false
}
```

**Response:** Full player state.

**Errors:**
- `409` — `PLAYER_ACTIVE`

---

### `POST /api/player/next`

Advance to the next queued track. User queue drains before radio/context queue. When a server-resolved `context_ref` is active, advances the context cursor instead (dual-pop on both orders — no discovery). Returns `404` when the queue is empty.

**Response:** Full player state.

**Errors:**
- `202` — Radio generation still `pending` and both queues empty: body is the full state with `radio_status: "pending"` — the queue is not ready yet, keep playing the current track and wait for the SSE `ready` event (do not treat it as a stop signal). Also returned (with `context_status: "pending"`) while an async context is still resolving and the user queue is empty.
- `404` — Queue genuinely empty (incl. `radio_status: "failed"`)

---

### `POST /api/player/previous`

Step back one track. Restores the previous track at position 0. Re-inserts the skipped track at the head of the queue it came from (or the context cursor when a `context_ref` is active).

**Response:** Full player state.

**Errors:**
- `404` — No history to go back to

---

### `POST /api/player/user-queue`

Add a track to the user queue (Spotify-style "add to queue"). Plays before the radio/context queue. **Duplicates are allowed** — the same track may be queued multiple times; each add appends a new instance.

**Request Body:**
```json
{
  "track": {
    "track_id": "dz_123",
    "title": "Song Title",
    "artists": ["Artist"],
    "album": "Album",
    "duration_seconds": 210,
    "cover_url": "/api/tracks/cover/dz_123",
    "stream_url": "/api/tracks/stream/dz_123"
  }
}
```

**Response:** Full player state.

---

### `DELETE /api/player/user-queue`

Empty the user queue. Also wiped automatically after ~30 min without heartbeats.

**Response:** Full player state.

---

### `DELETE /api/player/user-queue/item`

Remove ONE item from the user queue (Spotify-style single removal). Because duplicates are allowed, the item is addressed by its **live position** (index into the current `user_queue` array in the state snapshot, `0` = next to play), cross-checked against the client's `track_id`.

**Request Body:**
```json
{
  "track_id": "dz_123",
  "position": 2
}
```

**Errors:**
- `404` — `position` out of range (queue shrank under the client).
- `409 USER_QUEUE_STALE` — the `track_id` at `position` no longer matches (queue changed under the client, e.g. another device added). Re-fetch `GET /api/player/state` and retry.

**Response:** Full player state.

---

### `POST /api/player/user-queue/reorder`

Move ONE user-queue item to a new position (Spotify-style reorder). Same addressing as the single removal: current `position` + `track_id` cross-check, plus the destination `to_position` (index in the current `user_queue` array).

**Request Body:**
```json
{
  "track_id": "dz_123",
  "position": 2,
  "to_position": 0
}
```

**Errors:**
- `404` — `position` or `to_position` out of range.
- `409 USER_QUEUE_STALE` — the `track_id` at `position` no longer matches.

**Response:** Full player state.

---

### `POST /api/player/context/toggle`

Flip the active order of the current server-resolved context between `linear` and `shuffled`. The played/unplayed state is preserved (both orders are always dual-popped in sync), and the cursor resets to `0`. No request body.

**Response:** Full player state, with `context_order_active` flipped.

**Errors:**
- `404` — No active context to toggle

---

### `POST /api/player/context/reshuffle`

Regenerate the shuffled order from the current linear order, keeping only unplayed tracks, and reset the cursor to `0`. No request body.

**Response:** Full player state with the fresh `queue` window.

**Errors:**
- `404` — No active context to reshuffle

---

## 3. Tracks

### `GET /api/tracks`

List all locally downloaded tracks (status `completed` with a local file).

**Response `200 OK`:**
```json
{
  "status": "success",
  "count": 42,
  "tracks": [...]
}
```

---

### `GET /api/tracks/{video_id}`

Get full metadata for a track (title, artists, lyrics, URLs). Works for any download status.

**Response `200 OK`:** Track metadata object with `track_id`, `title`, `artists`, `album`, `duration_seconds`, `cover_url`, `stream_url`, `download_status`, etc.

**Errors:**
- `404` — Track not found

---

### `GET /api/tracks/stream/{track_id}`

Stream audio with seeking support (HTTP Range Requests). Auto-downloads if not yet downloaded.

**Headers:** `Range: bytes=0-1024` (optional)

**Response:**
- `200 OK` — Full file
- `206 Partial Content` — Range response

**Auto-download behavior:** If the track is missing, the backend resolves the Deezer source, starts a background download, polls up to 30s, then streams.

**Errors:**
- `409` — `MATCH_SELECTION_REQUIRED` (resolution needed)
- `404` — `TRACK_UNAVAILABLE` / `TRACK_FILE_MISSING`
- `503` — Provider unavailable
- `504` — Download timed out

---

### `GET /api/tracks/download/{track_id}`

Download a track for offline listening. Same auto-download contract as `/stream`.

**Response:** Audio file with `Content-Disposition: attachment`.

---

### `GET /api/tracks/cover/{track_id}`

Get album cover art. Returns local cached file or 302 redirect to CDN.

**Headers:** `Cache-Control: private, max-age=86400`

**Response:**
- `200 OK` — Local JPEG file
- `302 Found` — Redirect to CDN URL

**Errors:**
- `404` — Cover not found

---

### `POST /api/tracks/download/{track_id}`

Queue a track for download. Accepts a YouTube `video_id` or `dz_<int>`.

**Response `202 Accepted`:** Download queued.

**Errors:**
- `409` — `MATCH_SELECTION_REQUIRED`
- `404` — `TRACK_UNAVAILABLE`
- `503` — Provider unavailable
- `422` — Could not resolve

---

### `GET /api/tracks/{track_id}/resolution`

Get the current resolution request for a track.

**Response `200 OK`:** Resolution request with candidates.

**Errors:**
- `404` — No resolution request

---

### `POST /api/tracks/{track_id}/resolution`

Select a stored candidate and queue its download.

**Request Body:**
```json
{
  "resolution_id": "uuid",
  "video_id": "yt_video_id"
}
```

**Response `202 Accepted`:** Download queued.

---

### `POST /api/tracks/{track_id}/resolution/search`

Run a user-typed YouTube Music search and refresh candidates.

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `q` | string (min 1 char) | Custom search query |

**Response `200 OK`:** Updated resolution request with new candidates.

---

### `DELETE /api/tracks/{track_id}/resolution`

Cancel an owned resolution request.

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `resolution_id` | string (optional) | Specific resolution to cancel |

**Response `204 No Content`**

---

### `POST /api/tracks/{track_id}/resolution/reopen`

Reopen a stored source for fresh resolution.

**Response `200 OK`:** Reopened resolution request.

---

### `GET /api/tracks/{track_id}/album`

Get the album browse ID for a track.

**Response `200 OK`:**
```json
{
  "album_id": "dz_12345",
  "album_name": "Album Name",
  "source": "local"
}
```

---

### `GET /api/tracks/{track_id}/discovery`

Compose a radio queue for a seed track (Deezer-only). Tiers: album sibling, same-artist, similar artists.

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `limit` | int (1–50, default 15) | Max candidates |

**Response `200 OK`:**
```json
{
  "seed": "dz_123",
  "queue": [
    { "track_id": "dz_abc", "title": "...", "artists": [...], ... }
  ]
}
```

If seed has no Deezer identity:
```json
{
  "seed": "dz_local_123",
  "reason": "seed_without_deezer_identity",
  "queue": []
}
```

---

### `GET /api/tracks/{video_id}/related`

Get related songs, playlists, and artists from YouTube Music's "Related" tab.

**Response `200 OK`:**
```json
{
  "video_id": "abc123",
  "sections": [
    { "title": "You might also like", "items": [...] },
    { "title": "Recommended playlists", "items": [...] },
    { "title": "Similar artists", "items": [...] }
  ]
}
```

---

## 4. Search

### `GET /api/search`

Search music. Local-first, YouTube Music fallback.

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `q` | string | Search query (required) |
| `remote` | bool (default false) | Force YouTube Music search even if local results exist |

**Response `200 OK`:** Search results with tracks, playlists, albums, artists.

**Errors:**
- `400` — Empty query
- `503` — YouTube Music unavailable

---

## 5. Playlists & Favorites

### `GET /api/favorites`

Get the user's liked songs. Returns all by default, or paginated with `limit`/`offset`.

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `offset` | int (default 0) | Pagination offset |
| `limit` | int (default -1) | Max items (-1 = all) |

**Response Headers:** `X-Total-Count: 482`

**Response `200 OK`:**
```json
[
  {
    "track_id": "dz_123",
    "video_id": "dz_123",
    "title": "Song Title",
    "artists": ["Artist"],
    "album": "Album",
    "duration_seconds": 210,
    "download_status": "completed",
    "added_at": "2026-08-19T22:30:00Z",
    "favorited_at": "2026-08-19T22:30:00Z",
    "cover_url": "/api/tracks/cover/dz_123",
    "stream_url": "/api/tracks/stream/dz_123"
  }
]
```

**Notes:** `added_at` is the canonical field. `favorited_at` is a backward-compatible alias with the same value.

---

### `GET /api/favorites/{track_id}`

Check whether a track is in the user's favorites.

**Response `200 OK`:**
```json
{ "is_favorite": true }
```

---

### `POST /api/favorites/{track_id}`

Add a track to favorites. Caches as metadata-only `discovered` row — no download triggered.

**Response `201 Created`:**
```json
{ "favorite_id": "dz_123" }
```

**Errors:**
- `503` — Deezer provider unavailable
- `422` — Could not cache track metadata

---

### `DELETE /api/favorites/{track_id}`

Remove a track from favorites.

**Response `200 OK`:**
```json
{ "favorite_id": "dz_123" }
```

---

### `GET /api/playlists`

List the user's playlists.

**Response `200 OK`:** Array of playlist objects.

---

### `GET /api/playlists/{playlist_id}`

Get playlist details + tracks. Owner always; non-owners only if public. Supports `dz_<int>` for Deezer browse.

**Response `200 OK`:** Playlist object with tracks array.

---

### `POST /api/playlists`

Create a new playlist.

**Request Body:**
```json
{
  "name": "My Playlist",
  "description": "A cool playlist",
  "is_public": false
}
```

**Response `201 Created`:**
```json
{ "playlist_id": 42, "name": "My Playlist" }
```

---

### `PUT /api/playlists/{playlist_id}`

Update playlist details (owner only). Partial update — only provided fields change.

**Request Body:**
```json
{
  "name": "New Name",
  "description": "New description",
  "is_public": true
}
```

**Response `200 OK`:**
```json
{ "status": "updated" }
```

---

### `DELETE /api/playlists/{playlist_id}`

Delete a playlist (owner only).

**Response `200 OK`:**
```json
{ "status": "deleted" }
```

---

### `POST /api/playlists/{playlist_id}/save`

Save a public playlist to your library. Any user can save any readable playlist.

**Response `201 Created`:**
```json
{ "status": "saved", "playlist_id": 42 }
```

---

### `DELETE /api/playlists/{playlist_id}/save`

Unsave a playlist from your library. Idempotent.

**Response `200 OK`:**
```json
{ "status": "unsaved", "playlist_id": 42 }
```

---

### `POST /api/playlists/{playlist_id}/cover`

Upload a cover image for a playlist (owner only).

**Request:** `multipart/form-data` with `file` field.

**Response `200 OK`:**
```json
{ "cover_url": "/api/playlists/42/cover" }
```

---

### `GET /api/playlists/{playlist_id}/cover`

Serve the playlist cover image. Owner always; non-owners only if public.

**Response:** JPEG file.

**Errors:**
- `404` — Cover not found

---

### `POST /api/playlists/{playlist_id}/tracks`

Add a track to a playlist (owner only). Caches unknown tracks as `discovered`.

**Request Body:**
```json
{ "track_id": "dz_123" }
```

**Response `201 Created`:**
```json
{ "status": "added", "track_id": "dz_123" }
```

---

### `DELETE /api/playlists/{playlist_id}/tracks`

Remove a track from a playlist (owner only).

**Request Body:**
```json
{ "track_id": "dz_123" }
```

**Response `200 OK`:**
```json
{ "status": "removed", "track_id": "dz_123" }
```

---

### `PUT /api/playlists/{playlist_id}/tracks/reorder`

Reorder tracks in a playlist (owner only).

**Request Body:**
```json
{ "new_order": ["dz_321", "dz_123", "dz_456"] }
```

**Response `200 OK`:**
```json
{ "status": "reordered", "new_order": ["dz_321", "dz_123", "dz_456"] }
```

---

### `GET /api/playlists/{playlist_id}/tracks`

Get the tracks of a playlist (ownership-aware).

**Response `200 OK`:** Array of track objects.

---

### `GET /api/playlists/{playlist_id}/download`

Offline-download manifest for a playlist (owner only). Pure read — no enqueueing.

**Response `200 OK`:**
```json
{
  "playlist_id": 42,
  "tracks": [
    {
      "track_id": "dz_123",
      "title": "Song",
      "download_status": "completed",
      "download_url": "/api/tracks/download/dz_123"
    }
  ]
}
```

---

### `POST /api/playlists/{playlist_id}/download`

Enqueue every not-yet-ready track in the playlist (owner only). Returns the fresh manifest.

**Response `202 Accepted`:** Fresh download manifest.

---

### `POST /api/history`

Record a listen for a track.

**Request Body:**
```json
{ "track_id": "dz_123" }
```

**Response `201 Created`:**
```json
{ "status": "recorded", "track_id": "dz_123" }
```

---

### `POST /api/history/sync`

Batch-flush offline listens. Each listen carries its original `played_at` timestamp for correct ordering.

**Request Body:**
```json
{
  "listens": [
    {
      "track_id": "dz_123",
      "played_at": "2026-08-19T22:30:00Z",
      "client_id": "uuid-generated-by-client"
    }
  ]
}
```

**Response `200 OK`:**
```json
{ "synced": 5, "skipped": 0 }
```

**Errors:**
- `422` — Batch too large (max 1000)

---

### `GET /api/history`

Get the user's listening history.

**Response `200 OK`:**
```json
{ "records": [...] }
```

---

### `GET /api/history/statistics`

Get aggregated listening statistics.

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `period` | string | `1m`, `6m`, `1y`, `all` (default) |

**Response `200 OK`:** Statistics object with top tracks, artists, etc.

---

## 6. Albums

### `GET /api/albums/local`

List all locally-created albums (curator-created). IDs start with `local_album_`.

**Response `200 OK`:**
```json
{
  "status": "success",
  "count": 5,
  "albums": [...]
}
```

---

### `GET /api/albums/{album_id}`

Get album details with local download status for each track. Cached in DB after first fetch.

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `refresh` | bool (default false) | Force fresh fetch from YouTube Music |

**Response `200 OK`:** Album detail object with tracks array.

---

### `POST /api/albums/download/{album_id}`

Download all tracks from an album. Returns immediately.

**Response `202 Accepted`:**
```json
{
  "queued": 10,
  "already_downloaded": 2,
  "needs_resolution": 0
}
```

---

### `GET /api/albums/cover/{album_id}`

Serve the cover art for an album.

**Response:** JPEG file with `Cache-Control: public, max-age=86400`.

**Errors:**
- `404` — Album or cover not found

---

## 7. Artists

### `GET /api/artists/local`

List all locally-created artist profiles (curator-created).

**Response `200 OK`:**
```json
{
  "status": "success",
  "count": 10,
  "artists": [...]
}
```

---

### `GET /api/artists/local/{artist_id}`

Get a locally-created artist profile with all library tracks by that artist.

**Response `200 OK`:** Artist detail object with tracks array.

**Errors:**
- `404` — Local artist not found

---

### `GET /api/artists/by-name/{name}`

Case-insensitive exact-name lookup against the unified artists directory.

**Response `200 OK`:**
```json
{
  "status": "success",
  "query": "Pink Floyd",
  "count": 1,
  "artists": [{ "id": "UC...", "name": "Pink Floyd", "is_local": false }]
}
```

---

### `GET /api/artists/directory`

Paginated listing of the unified artists directory (YouTube + local).

**Query Params:**
| Param | Type | Description |
|---|---|---|
| `limit` | int (1–200, default 50) | Page size |
| `offset` | int (default 0) | Page offset |

**Response `200 OK`:**
```json
{
  "status": "success",
  "count": 150,
  "limit": 50,
  "offset": 0,
  "artists": [...]
}
```

---

### `GET /api/artists/cover/{artist_id}`

Serve the cover photo for an artist. Local file → CDN redirect → lazy Deezer fetch.

**Response:**
- `200 OK` — Local JPEG file
- `302 Found` — Redirect to CDN

---

### `GET /api/artists/{channel_id}`

Get artist details. Polymorphic by ID:
- `dz_<int>` → Deezer data
- `UC...` → YouTube Music data
- `local_artist_<uuid12>` → local profile

**Response `200 OK`:** Artist detail with discography sections.

---

## 8. Import

### `POST /api/import/csv`

Import tracks from a Spotify CSV export (Exportify format). Max 2000 rows.

**Request:** `multipart/form-data` with `file` field (.csv).

**Required CSV columns:** `Track Name`, `Artist Name(s)`, `Duration (ms)` (optional).

**Routing logic:** `Liked_Songs.csv` → adds matched tracks to favorites. Other filenames → creates a private playlist named after the file.

**Response `202 Accepted`:**
```json
{
  "job_id": "uuid",
  "total_rows": 150,
  "status": "processing"
}
```

**Errors:**
- `400` — Invalid CSV / empty / too many rows
- `503` — Music services unavailable

---

### `GET /api/import/status/{job_id}`

Get the current status of an import job.

**Response `200 OK`:**
```json
{
  "job_id": "uuid",
  "status": "processing",
  "total_rows": 150,
  "completed": 120,
  "matched": 100,
  "failed": 20,
  "review": 15,
  "unavailable": 5
}
```

---

### `GET /api/import/list`

List the user's import jobs (newest first).

**Response `200 OK`:** Array of job summaries.

---

### `POST /api/import/jobs/{job_id}/cancel`

Cancel a running import job. Exits at the next row boundary.

**Response `200 OK`:**
```json
{ "status": "cancelled" }
```

---

### `POST /api/import/resolution/{resolution_id}`

Select a collected import candidate and continue that row.

**Request Body:**
```json
{ "candidate_id": "string" }
```

**Response `202 Accepted`:** Row continues processing.

---

### `POST /api/import/resolution/{resolution_id}/search`

Search an import resolution with a user-provided query.

**Request Body:**
```json
{ "query": "string" }
```

**Response `200 OK`:** Updated candidates.

---

### `POST /api/import/resolution/{resolution_id}/retry`

Retry a collected provider lookup.

**Response `202 Accepted`:** Retry queued.

---

### `POST /api/import/resolution/{resolution_id}/skip`

Skip one import row without selecting or downloading.

**Response `200 OK`:**
```json
{ "status": "skipped" }
```

---

## 9. Curator

> All curator endpoints require role `curator` or `admin`.

### `POST /api/curator/tracks/upload`

Upload a local audio file directly to the library.

**Request:** `multipart/form-data`:
| Field | Type | Required |
|---|---|---|
| `file` | audio file | yes |
| `cover` | image file | yes (for new tracks) |
| `title` | string | yes |
| `artists` | string | yes (comma-separated) |
| `album` | string | no |
| `target_track_id` | string | no (bind to existing unresolved track) |

**Supported formats:** MP3, M4A, FLAC, OGG, OPUS, WAV, AAC.

**Without `target_track_id`:** Mints a synthetic `local_{uuid12}` id, marks as `completed`.

**With `target_track_id`:** Binds the upload to an existing track in `unavailable`/`needs_resolution`/`discovered` state. No cover needed.

**Response `201 Created`:**
```json
{
  "status": "created",
  "track_id": "local_abc123def456",
  "title": "Song Title",
  "artists": ["Artist"],
  "album": "Album",
  "duration": 210,
  "cover_url": "/api/tracks/cover/local_abc123def456",
  "stream_url": "/api/tracks/stream/local_abc123def456",
  "metadata_url": "/api/tracks/local_abc123def456"
}
```

---

### `POST /api/curator/tracks/from-youtube`

Add a track from a single-track YouTube/YouTube Music link. Treated as LOCAL — never goes through Deezer matching.

**Request Body:**
```json
{ "url": "https://music.youtube.com/watch?v=O0jxbzUqWXw" }
```

**Accepted links:** `watch?v=<id>`, `youtu.be/<id>`. Extra params (e.g. `list=...`) are ignored.

**Rejected:** Playlists, albums, Shorts, non-video URLs.

**Behavior:** Downloads audio on the streaming (high-priority) bucket. If track is already `pending` (queued by background job), escalates to streaming.

**Response `201 Created`:** Track object with `track_id`, `title`, etc.

**Errors:**
- `422` — Invalid YouTube link
- `503` — YouTube metadata fetch failed

---

### `PUT /api/curator/tracks/{track_id}`

Partially update a track's metadata. Only provided fields change.

**Request Body:**
```json
{
  "title": "New Title",
  "artist_ids": ["UC...", "local_artist_..."],
  "album_id": "dz_123",
  "lyrics": "Full lyrics text",
  "lyrics_lrc": "[00:10.00] Timed lyrics..."
}
```

**Response `200 OK`:**
```json
{ "status": "updated", "track_id": "dz_123" }
```

---

### `POST /api/curator/tracks/{track_id}/cover`

Replace the cover art for a track.

**Request:** `multipart/form-data` with `file` field (image).

**Response `200 OK`:**
```json
{
  "status": "updated",
  "track_id": "dz_123",
  "cover_path": "/path/to/cover.jpg",
  "cover_object_key": "covers/dz_123.jpg",
  "cover_sync_pending": false
}
```

---

### `POST /api/curator/albums`

Create a local album from existing library tracks.

**Request Body:**
```json
{
  "title": "Album Title",
  "artist_ids": ["UC...", "local_artist_..."],
  "year": 2024,
  "track_ids": ["dz_123", "dz_456", "dz_789"]
}
```

**Response `201 Created`:**
```json
{
  "status": "created",
  "id": "local_album_abc123def456",
  "title": "Album Title",
  "track_count": 3,
  "skipped_track_ids": [],
  "album_url": "/api/albums/local_album_abc123def456"
}
```

---

### `POST /api/curator/albums/{album_id}/cover`

Upload a custom cover for a local album.

**Request:** `multipart/form-data` with `file` field (image).

**Response `200 OK`:**
```json
{ "status": "updated", "album_id": "...", "cover_path": "..." }
```

---

### `POST /api/curator/artists`

Create a local artist profile.

**Request Body:**
```json
{
  "name": "Artist Name",
  "bio": "Optional bio"
}
```

**Response `201 Created`:**
```json
{
  "status": "created",
  "artist_id": "local_artist_abc123def456",
  "name": "Artist Name",
  "artist_url": "/api/artists/local/local_artist_abc123def456"
}
```

---

### `POST /api/curator/artists/{artist_id}/cover`

Upload or replace the cover photo for a local artist.

**Request:** `multipart/form-data` with `file` field (image).

**Response `200 OK`:**
```json
{ "status": "updated", "artist_id": "...", "cover_path": "..." }
```

---

## 10. Admin

> All admin endpoints require role `admin`.

### `GET /api/admin/users/pending`

List users awaiting approval.

**Response `200 OK`:**
```json
{ "status": "success", "pending_users": [...] }
```

---

### `GET /api/admin/users`

List all users.

**Response `200 OK`:**
```json
{ "status": "success", "users": [...] }
```

---

### `POST /api/admin/users/{username}/approve`

Approve a user.

**Response `200 OK`:**
```json
{ "status": "success", "message": "Admin approved the user: username" }
```

---

### `POST /api/admin/curator/{username}`

Promote a user to curator role.

**Response `200 OK`:**
```json
{ "status": "success", "message": "Promoted user username to curator" }
```

---

### `GET /api/admin/stats`

Library statistics (tracks per status, disk usage, users).

**Response `200 OK`:**
```json
{ "status": "success", "stats": { ... } }
```

---

### `GET /api/admin/orphans`

Find orphaned records and files (DB rows without files, files without DB rows).

**Response `200 OK`:**
```json
{ "status": "success", "orphans": { "records_without_file": [...], "files_without_record": [...] } }
```

---

### `POST /api/admin/retry-failed`

Retry all tracks with `download_status = 'failed'`.

**Response `200 OK`:**
```json
{ "status": "success", "retried_count": 12 }
```

---

### `DELETE /api/admin/tracks/{track_id}`

Delete a single track and its unreferenced local/remote assets. The track must not currently be downloading.

**Response `200 OK`:**
```json
{ "status": "success", "message": "Track dz_123 deleted successfully" }
```

---

### `DELETE /api/admin/tracks`

Bulk delete tracks atomically. S3 cleanup enabled by default.

**Request Body:**
```json
{
  "track_ids": ["dz_123", "dz_456"],
  "delete_remote_assets": true
}
```

**Limits:** Max 500 track IDs per request.

**Response `200 OK`:** Deletion report with per-track status.

---

### `POST /api/admin/covers/sync`

Resume mirroring legacy/local track covers to S3.

**Response `200 OK`:** Sync status.

---

### `GET /api/admin/youtube-cookies`

YouTube cookie file diagnostics: existence, required auth cookies present, last modified. Cookie names only — never values.

**Response `200 OK`:**
```json
{
  "status": "success",
  "cookies": {
    "path": "/app/youtube_cookies.txt",
    "exists": true,
    "size_bytes": 6142,
    "modified_at": "2026-08-18 13:21:45",
    "present": ["SAPISID", "SID", "HSID", "__Secure-1PSID"],
    "missing": []
  }
}
```

---

### `POST /api/admin/youtube-cookies`

Upload a fresh YouTube cookies.txt (Netscape format).

**Request:** `multipart/form-data` with `file` field.

**Response `200 OK`:**
```json
{ "status": "success", "message": "Cookies updated" }
```

---

## 11. Health

### `GET /api/health`

Health check endpoint. No authentication required.

**Response `200 OK`:**
```json
{ "status": "healthy" }
```

---

## Error Response Format

All error responses follow this shape:

```json
{
  "detail": "Human-readable error message"
}
```

Some errors include structured codes:

```json
{
  "detail": {
    "code": "PLAYER_ACTIVE",
    "device_id": "flutter_abc",
    "device_name": "Gio's iPhone"
  }
}
```

---

## Authentication Notes

- **Access tokens** expire after 15 minutes. Use `POST /api/auth/refresh` with the refresh token to get a new pair.
- **Refresh tokens** are valid for 14 days and slide on each refresh. If unused for 14 days, re-login is required.
- **Multi-device login:** Each login creates a separate session row. Revoking one device does not affect others.
- **Cookie fallback:** The SSE endpoint (`/api/player/events`) uses `httponly` cookies because EventSource cannot send Authorization headers. The cookie is set at login and scoped to `/api/tracks`.
- **Password change:** All sessions are revoked on success — every device must re-login.

---

## Queue Mode Summary

| Mode | Who owns the queue | Discovery | Use case |
|---|---|---|---|
| `radio` | Server (auto-refilled) | Runs (Deezer graph) | Single-track play, search, discovery |
| `context` | Frontend (pushed via PUT `queue: [...]`) | Never | Ad-hoc / local files / search-origin tracks |
| `context` + `context_ref` | Server (resolved once) | Never | Playlists, albums, favorites |

**With `context_ref`, the server resolves the full ordered list once** and walks a cursor — so >50 track playlists are handled without frontend batching. The wire `queue` is a 50-track display window, but `queue_count`/`context_total` reflect the real remaining size and `next` keeps working to the end.

**Queue drain order:** User queue → Radio/Context queue.

**Max stored queue:** 50 tracks (the display window).

---

## SSE Event Types

| Event | Description |
|---|---|
| `state` | Full player state snapshot (on connect + every mutation) |
| `library` | Library change notification (`favorites` / `playlists` / `history` + `added` / `removed` / `updated` / `created` / `deleted`) |
| `track_status` | Track download status change |
| `sse_closed` | Connection kicked (per-user limit exceeded) |
| `: ping` | Keep-alive every ~20s |
