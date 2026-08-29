# APIs.md ↔ Frontend Cross-Check Report

**Scope:** `APIs.md` (updated backend reference, 1724 lines) cross-checked against the Flutter client in `packages/zephyr_core` — API client `lib/api/zephyr_api.dart`, models `lib/models/models.dart`, providers (`player_provider`, `library_provider`, `auth_provider`, `offline_provider`), and consuming screens/widgets.

**Method:** Every documented endpoint was diffed against every `_dio` call in the client; field-level contracts (state snapshot keys, SSE event types, error envelopes, status codes) were traced through providers and screens.

---

## Verdict

Endpoint coverage is effectively **1:1** — every endpoint the docs define that this app needs is implemented with matching method + path (the only unused doc endpoint is `GET /api/health`, which a UI client doesn't need). The Exchange 59/60 async radio + server-resolved context work is implemented faithfully and in depth (`radio_status` / `radio_request_id` / `radio_generation` stale-guards, 202-not-stop handling for `/next`, `context_ref` mutual exclusion with `queue`, dual-order cursor semantics via toggle/reshuffle, user-queue position+track_id addressing with `USER_QUEUE_STALE` recovery).

However there are **3 real contract divergences**, **1 functional gap**, and several doc gaps worth reconciling.

---

## 🔴 Divergences (docs say one thing, client implements another)

### 1. `GET /api/player/devices` response shape
- **Docs:** returns a bare JSON array: `[{device_id, device_name, is_player, is_alive}]`.
- **Client** (`zephyr_api.dart:758-768`): expects a wrapper object `{ "devices": [...] }`; if the body isn't a Map with a `devices` list it silently returns `[]`.
- **Impact:** If the backend really ships the documented bare array, the device picker (via HTTP refresh) always sees an empty list. The feature currently only works because the *undocumented* typed SSE `devices` event also feeds `connectedDevices` (player_provider lines 1009-1035).
- **Fix direction:** agree which side is current; either unwrap an array in `getConnectedDevices()` (tolerant parse) or fix the doc.

### 2. Import job status/progress field names
- **Docs §8** (`GET /api/import/status/{job_id}`, and POST `/api/import/csv` returning `total_rows`): fields are `job_id, status, total_rows, completed, matched, failed, review, unavailable`.
- **Client**: reads `total`, `processed`, `queued`, `needs_review` (+`failed`, `unavailable`) — in three places:
  - `ImportStatus.fromJson` (models.dart:1055-1086),
  - the manual parse of the csv-upload response (`zephyr_api.dart:1631-1645`),
  - the SSE import-progress handler (`import_screen.dart:49-58`).
- **Impact:** With the documented shape, totals/progress/review counts render as 0 and per-row progress never advances.
- Also undocumented-but-used by the client on these payloads: `status_url`, `import_mode`, `playlist_name`, `created_at`, `queued`, `failed_tracks[]`, `review_items[]`.

### 3. Error-response envelope
- **Docs:** errors are `{"detail": "…"}` and structured codes are nested under detail (`{"detail": {"code": "PLAYER_ACTIVE", …}}`).
- **Client** (`_handleDioError`, zephyr_api.dart:2055-2112): parses structured codes at the **top level** of the body (`data['code']`, `data['message']`, `data['missing_ids']`), not `detail.code`. Special cases that would silently break if codes truly live under `detail`:
  - `PLAYER_ACTIVE` → `PlayerActiveException` (also parsed top-level at zephyr_api.dart:688-696 and 747-753),
  - `USER_QUEUE_STALE` → `UserStaleQueueException`,
  - `MATCH_SELECTION_REQUIRED` / `TRACK_UNAVAILABLE` / `PROVIDER_UNAVAILABLE` typed exceptions,
  - generic `data['detail']`/`data['message']` string fallbacks.
- Note: only `ResolutionRequiredException.fromJson` checks both root **and** `detail.*`. If the backend nests everything under `detail`, takeover dialogs, queue-stale recovery, and resolution flows degrade to raw-string errors.
- **Fix direction:** confirm the wire truth once, then either change the docs' "Error Response Format" section or normalize parsing to try both.

---

## 🟠 Functional gap vs the new contract

### 4. Remote `play_track` never sends `seed_radio`
- **Docs:** `POST /api/player/command` supports optional `seed_radio` for `play_track`; `seed_radio: true` is "**the ONLY fresh-radio trigger**" — send it on search-result plays.
- **Client** (`sendPlayerCommand`, zephyr_api.dart:702-731; called from player_provider:2290-2327): remote dispatch sends `action/current_track_id/origin/contextRef` but **never `seed_radio`**, even when `origin == 'search' | 'radio'` (locally it optimistically sets `radioStatus: pending`). Locally-owned devices do send `seed_radio: true` via `PUT /api/player/state` (player_provider:2927-2934 & 3052-3062), so only remotely-initiated search plays hit this.
- Additionally, `context_ref` **is sent** in command payloads but is not listed in the doc's request-body table.

---

## 🟡 Doc gaps (client behavior not covered by APIs.md)

| Item | Detail |
|---|---|
| SSE `devices` event | Client consumes a typed `devices` SSE event carrying the full device list (player_provider:1009-1035). Not in the "SSE Event Types" table. |
| SSE `import_progress` event | Client subscribes to a typed `import_progress` event for live import rows (zephyr_api.dart:861-885, import_screen). Not in the table. |
| Client synthesizes `_sse_initial` | Docs say the server marks reconnect snapshots with `_sse_initial: true`; the client additionally sets it itself after a reconnect refetch (zephyr_api.dart:826-836). Harmless but worth documenting who owns the flag. |
| Curator upload extra field | `POST /api/curator/tracks/upload` also sends `duration` (zephyr_api.dart:1911) — absent from the docs' field table. |
| Curator track update extra field | `PUT /api/curator/tracks/{id}` also sends plain `album` alongside documented `album_id` (zephyr_api.dart:1951-1952). |
| Cookies-upload 422 detail | Client expects `{"detail": {"missing": [...], "message": …}}` from failed YouTube-cookie uploads (zephyr_api.dart:1811-1824) — undocumented error shape. |
| Bulk-delete cap | Docs limit bulk delete to 500 ids; the client performs no client-side chunking/cap enforcement. |
| Unused state fields | `refilled` and `player_heartbeat_at` from `GET /api/player/state` are never read by the client. |
| Unused endpoints | `GET /api/health` and `GET /api/albums/cover/{album_id}` are never called (covers arrive as `cover_url` on payloads; artist covers use `/api/artists/{id}/cover` via header-authenticated image loading). |

---

## ✅ Verified aligned

- **Auth:** form-urlencoded login, refresh rotation via `Authorization: Bearer <refresh_token>` (single-flight + interceptor retry on 401), logout with refresh token, change-password payload, `role` / `is_approved` / `must_change_password` consumed, JWT-expiry proactive refresh (60s buffer), register → "wait for admin approval" flow.
- **Player PUT/state:** ownership heartbeat (`device_id`/`device_name` only when owner), partial bodies, `origin` whitelist `queue|context`, seed Radio = `current_track_id` + `seed_radio: true` + `queue_mode: 'radio'`, queue-vs-`context_ref` mutual exclusion honored (queue omitted when context present), 50-track display window serialization.
- **Async radio contract:** `202` from `/next` treated as keep-playing-wait-for-SSE with retry-on-ready keyed by `radio_request_id` / `context_request_id` (stale-request guards match the documented `Exchange 59/60` semantics exactly); `radio_status` transitions including `failed` + `radio_error` handled.
- **Context endpoints:** `toggle` / `reshuffle` called without bodies, 404 → empty-map handling.
- **User queue:** add payload shape matches (incl. relative cover/stream URLs); duplicates allowed; single-remove/reorder addressed by `position` + `track_id` cross-check + `to_position`; `USER_QUEUE_STALE` triggers resync-and-retry.
- **Tracks:** proxy-stream via local loopback injecting Authorization + Range forwarding and typed error extraction (409/404/503 codes as documented); download id normalization (`123` → `dz_123`); album lookup; discovery `limit` param; related sections.
- **Favorites:** pagination params, `X-Total-Count` header read, `added_at` canonical with `favorited_at` fallback.
- **Playlists:** CRUD/save/unsave/cover multipart `file`/tracks add/remove/`reorder` `new_order`/download manifest & batch trigger, all matching methods, paths, and body shapes.
- **History/sync:** `{track_id, played_at (ISO UTC), client_id (uuid v4)}` offline buffer flushed in ≤1000-item chunks (matches max-batch rule).
- **Statistics:** period values `'1m'|'6m'|'1y'|'all'` match docs.
- **SSE transport:** Bearer header + manual `access_token` cookie fallback, `device_id`/`device_name` query params, reconnect backoff, `sse_closed` backoff-reconnect — all consistent with the docs' auth notes.
- **Albums/artists listings:** local albums/artists, polymorphic artist detail (`dz_…` / `UC…` / `local_artist_…` normalization), by-name lookup, directory paging params.
- **Admin:** pending/users lists, approve, promote-curator, stats/orphans extraction, retry-failed count, single & bulk delete payloads, covers sync, cookies GET/upload.

---

## Recommended actions

1. **Decide the devices-list shape** and either make `getConnectedDevices()` accept both array/wrapper or re-document §2 `GET /api/player/devices` (highest risk of silent breakage, masked today by SSE).
2. **Reconcile the import field names** (`total_rows/completed/matched/review` vs `total/processed/needs_review`) across docs, `ImportStatus.fromJson`, upload-parse, and the SSE progress handler — pick one vocabulary everywhere.
3. **Settle the error envelope**: if structured codes stay nested in `detail`, update `_handleDioError` + PLAYER_ACTIVE sites; otherwise drop the nested example from "Error Response Format".
4. Either implement `seed_radio` passthrough for remote `play_track` commands (and document `context_ref` in the command table) or document why remote seeding is intentionally omitted.
5. Add `devices` and `import_progress` rows to the SSE Event Types table.

---

## Resolution Log (fixed this session)

> Docs are treated as backend truth; client-side fixes therefore make parsing tolerant of the documented shape while keeping backward compatibility.

1. ✅ **Devices shape** — `getConnectedDevices()` (`zephyr_api.dart`) now accepts a bare array *or* `{devices: [...]}`.
2. ✅ **Import vocabulary** — dual-spelling support added in all three readers:
   - `ImportStatus.fromJson` (`models.dart`): `total|total_rows`, `processed|completed`, `needs_review|review`.
   - csv-upload response parse (`zephyr_api.dart importCsv`): `total|total_rows`.
   - SSE progress handler (`import_screen.dart`): local `field(key, alias?)` helper covering both vocabularies.
3. ✅ **Error envelope** — `_handleDioError` flattens root body + nested `detail` map into one lookup (mirroring the stream proxy's normalization) for `USER_QUEUE_STALE`, `MATCH_SELECTION_REQUIRED`, `TRACK_UNAVAILABLE`, `PROVIDER_UNAVAILABLE`, `missing_ids`; two new helpers `_errorCodeMatches()` / `_errorField()` make both `PLAYER_ACTIVE` sites (PUT state catch + takeover catch) shape-agnostic.
4. ✅ **Remote seeding** — `sendPlayerCommand()` gained a `seedRadio` param mapped to the documented `seed_radio` field (sent only for `play_track`); the remote-dispatch call site in `player_provider.dart` now passes `seedRadio: shouldSeedRadio` and suppresses `context_ref` when seeding ("radio wins"). Doc side: `POST /api/player/command` body table now documents `context_ref`.
5. ✅ **SSE table** — `devices` and `import_progress` events documented in APIs.md, including the note that `devices` supplements rather than replaces `GET /api/player/devices`.

**Verification:** `dart analyze packages/zephyr_core` → 0 errors, 0 warnings (23 pre-existing info-level lints, none introduced by these edits). Unit tests not executed: the Flutter tool wrapper needs to write its engine stamp into the read-only SDK cache under this sandbox.
