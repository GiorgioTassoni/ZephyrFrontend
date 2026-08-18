# Frontend Message — Backend Changes for the Frontend (Security, Performance & Hybrid Resolution)

> From: backend team
> To: frontend team
> Status (this message): **All of the following is live on the backend** and verified by the full test suite (217 passing). The security/performance items are from the audit pass; the **hybrid resolution** contract is the new track-resolution behavior shipped across Phase 3 of `safe-track-resolution-plan.md`. Treat everything below as "what you need to implement and test against the deployed endpoints."

---

## TL;DR

The frontend has **three hard action items**:

1. **S-03 — Token handling** (migrate everything to `Authorization: Bearer` headers).
2. **S-07 — Admin forced password rotation** (handle the new `must_change_password` flag and build a password-change flow).
3. **R-01 — Resolution UX** (new): tracks can now come back `409 MATCH_SELECTION_REQUIRED` with candidates, `404 TRACK_UNAVAILABLE`, or `503 PROVIDER_UNAVAILABLE` — you need the candidate modal, unavailable state, and "report wrong match" (reopen) flow described below.

> *S-06 — slide-on-refresh with strict no expiry is intentional design. **Do not modify** anything related to this item on either side; the auditor explicitly excluded it from the fix list.*

---

# Part A — Security & performance audit fixes

## Phase 1 — Critical security (shipped)

### S-04 — TLS verification enabled

`yt-dlp` no longer skips cert checks. No frontend action. Local-stack tooling that was relying on the bypass (e.g. mitmproxy) will need CA-trust updates separately.

### 🟡 S-03 — Token exposure via query string (HARD FRONTEND ACTION)

**Intended contract: tokens passed via URL query parameters return `401 Unauthorized` with no silent stripping and no fallback.** Migrate everything to `Authorization: Bearer <token>` headers.

**Frontend action items (in priority order):**

1. **Audit every request that sends a token.** Search for any fetch / axios / XHR / `<a href>` where a token is appended as `?token=…`, `?access_token=…`, `?refresh_token=…`, or any URL query parameter. Common surfaces:
   - `/api/tracks/stream/<video_id>`
   - `/api/tracks/download/<video_id>`
   - `<a href="…?token=…">` download anchors
   - `window.location` redirects that ever embedded auth
   - `<img src>` / `<frame>` that previously carried auth
2. **Move every one of those to the `Authorization: Bearer <token>` header.** Standard form:
   ```js
   fetch('/api/tracks/stream/xyz', {
     headers: { 'Authorization': `Bearer ${getAccessToken()}` },
     // do NOT append token to URL
   });
   ```
3. **Token-bearing redirects → blob download.** If any UI flow currently opens a tokenized URL in a new tab, switch to `fetch` + `Blob` + a programmatically-clicked `<a download>` anchor:
   ```js
   const res = await fetch(url, { headers: getAuthHeader() });
   const blob = await res.blob();
   const { href } = URL.createObjectURL(blob);
   const a = Object.assign(document.createElement('a'), { href, download: filename });
   a.click();
   URL.revokeObjectURL(href);
   ```
4. **No new query-string tokens anywhere.** Treat any new endpoint as header-only.
5. **Strip tokens from cached URLs.** If you store URLs (e.g. for replay-on-mount), strip the token before storing and re-inject via header at request time.

**Verification checklist (do in DevTools):**

- [ ] `window.location.search` never contains a token after any user action.
- [ ] DevTools Network tab: tokens appear only in `Authorization` request headers.
- [ ] No tokens in `console.log`, error reports, Sentry payloads, or third-party analytics SDK beacons.
- [ ] Reload-after-stream flows still succeed via header auth.
- [ ] The audit's previously-`200`-happy endpoints that used `?token=…` now return `401` (this is expected; clean them up, don't paper over).

### S-05 — Cookie file path from env

Moved out of hardcoded path into an env var. No production frontend impact.

---

## Phase 2 — Credentials & auth (shipped)

### 🟡 S-07 — Admin forced password rotation + strength validation (HARD FRONTEND ACTION)

#### What changed

1. **Admin seed validation.** `init_db()` validates `ADMIN_USER_PASSWORD` in `.env` at startup (length ≥ 12; ≥ 3 of 4 categories: lowercase, uppercase, digit, symbol; not in a small blocklist). If validation fails, the server **refuses to start**.
2. **Forced first-login rotation.** The admin account is created with `must_change_password = TRUE`, also set when an admin resets another user's password. The flag is returned in `/login` and `/refresh`. While `TRUE`, **every protected endpoint returns `403`** with a `password_rotation_required` error (except `/api/auth/change-password`).
3. **New endpoint: `POST /api/auth/change-password`** (contract below). On success the flag flips to `FALSE` and the session family is wiped, forcing a re-login.

#### Contract changes

| Endpoint | Change | Details |
|---|---|---|
| `POST /api/auth/login` | Response field added | `must_change_password: boolean`. |
| `POST /api/auth/refresh` | Response field added | `must_change_password: boolean` — sticky until rotation. |
| `POST /api/auth/change-password` | **New endpoint** | Requires `Authorization: Bearer <access_token>`. Body: `{ "current_password": "string", "new_password": "string" }`. `200` on success, `401` wrong current password, `400` strength/same-as-current failure. |
| All protected endpoints | `403` when rotation pending | `{ "error": "password_rotation_required", "must_change_password": true, "message": "Password must be rotated before using this endpoint." }` |

#### Frontend action items

1. **Handle `must_change_password` after login/refresh** — redirect to a password-change screen BEFORE the user hits any other route.
2. **Build a password-change screen** accessible without any other protected endpoint: current + new password fields; on `200` clear tokens and redirect to `/login`; on `400` show the backend validation message; on `401` show "Current password is incorrect".
3. **Block all other routes while the flag is `TRUE`** (server enforces; match it in UX).
4. **No new query-string tokens** — header-only like everything else.

#### Verification checklist

- [ ] Login as admin with the `.env` seed password → response has `must_change_password: true`.
- [ ] Any protected endpoint returns `403` with `password_rotation_required`.
- [ ] Password-change screen reachable and functional.
- [ ] After successful rotation → redirected to `/login`, must re-enter credentials.
- [ ] Subsequent logins return `must_change_password: false`.
- [ ] Weak new passwords return `400` with a clear message.

---

## Phase 3 & 4 — Stability, performance, refactoring (shipped)

### S-09 — LRU cap on metadata cache

No frontend action.

### S-08 — N+1 eliminated on album/artist hot paths

No contract change; album/artist pages will be snappier.

### Phase 4 — no contract changes expected

Audit gap fixes add observability (previously-silent failures may surface as noisy 5xx in dev — **should not reach normal users**). **Range parsing is now strict: `416 Range Not Satisfiable` is authoritative — drop any client-side `416` retry.**

---

# Part B — Hybrid resolution (NEW, shipped — R-01 HARD FRONTEND ACTION)

This is the behavior change behind `safe-track-resolution-plan.md` Phase 3. Its goal: **the app must never automatically store or download a YouTube source unless it passed strict matching or the user explicitly selected it.** The frontend must treat track resolution as a stateful flow, not "click download → file appears".

## What changed conceptually

Every download/stream/queue attempt now ends in one of four outcomes:

1. **High-confidence match** → `202` queued, download starts automatically.
2. **Ambiguous match** → `409 MATCH_SELECTION_REQUIRED` with candidate list; **nothing is downloaded** until the user picks.
3. **Unavailable** → `404 TRACK_UNAVAILABLE`; no source exists, nothing downloads.
4. **Provider outage** → `503 PROVIDER_UNAVAILABLE`; the source service (Deezer/YouTube) is temporarily down — retryable.

New `tracks.download_status` values: `pending | downloading | completed | failed | discovered | needs_resolution | unavailable`. `needs_resolution` / `unavailable` rows **never carry a YouTube source** (`yt_id` is null).

## Error-code contract (download & stream)

| HTTP | `code` | Meaning | Body |
|---|---|---|---|
| `202` | — | Queued / auto-matched / already done | queued shape (below) |
| `409` | `MATCH_SELECTION_REQUIRED` | Candidates need explicit user selection | see 409 shape (below) |
| `404` | `TRACK_UNAVAILABLE` | No plausible YouTube source | `{ "code": "TRACK_UNAVAILABLE", "message": "No safe YouTube Music match was found." }` |
| `503` | `PROVIDER_UNAVAILABLE` | Deezer/YouTube temporarily down | `{ "code": "PROVIDER_UNAVAILABLE", "message": "..." }` |
| `422` | `INVALID_RESOLUTION` (selection) / plain `detail` string (resolve) | Malformed id, invalid/expired selection, no-title track | see endpoints |
| `504` | — | A safe download is in progress but didn't finish in 30s (stream path) | `detail` string |

### 202 queued shape (unchanged for existing flows)

```jsonc
{
  "status": "queued",           // or "success" when already available locally
  "track_id": "dz_123",         // canonical id — ALWAYS the library identity
  "video_id": "dz_123",
  "yt_id": "safe_youtube_id",   // implementation detail — never the library identity
  "title": "Song title",
  "message": "Download queued...",
  "stream_url": "/api/tracks/stream/dz_123"
}
```

### 409 shape — the candidate modal payload

```jsonc
{
  "code": "MATCH_SELECTION_REQUIRED",
  "resolution_id": "uuid",          // required for the selection POST
  "track_id": "dz_123",
  "title": "Semicerchi",
  "artists": ["Expected Artist"],
  "duration_seconds": 214,
  "candidates": [
    {
      "video_id": "candidate_video_id",
      "title": "Candidate title",
      "artists": ["Candidate Artist"],
      "duration_seconds": 213,
      "video_type": "ATV",          // "ATV" (audio) or "OMV" (official music video)
      "thumbnail": "https://...",   // canonical key is always `thumbnail`
      "match_score": 82,
      "match_reasons": ["title_exact", "artist_exact"]
    }
  ]
}
```

**Frontend rules for the modal:**

- Show title, expected artists, expected duration, and for each candidate: title, artists, duration, type, artwork, match reasons.
- **Label OMV clearly as a video version** — OMV is manual-only by policy and must never appear silently preferred.
- Buttons: **Select** (POSTs the selection) and **Cancel** (DELETE, leaves the track unresolved, keeps the original intent uncommitted).
- Disable the Select button while a selection request is pending (prevent double-submit).
- Handle expired/selected requests by refreshing track state.
- Preserve the user's original intent (download, stream, favorite, playlist, album action) so it can continue after selection.

**Score semantics (Exchange 39 — feat-aware matching):**

- `match_score` is computed **after feat credits are stripped from both the source and the candidate title/artist** — `"This Is Love (feat. Eva Simons)"` matches a source `"This Is Love"` as `title_exact` (100), not `title_related` (68). The raw candidate title in the payload is unchanged; only the comparison is normalized. `match_reasons` includes `feat_variant` when a credit difference was bridged.
- **A `feat_variant` match is NOT a blocking signal** — the plain-vs-feat choice is decided by the server (auto-bind when unique, or by the tiebreak below). The modal's job is only to render.
- **Candidates are deduped server-side**: same normalized title + artists + duration (within 1s) collapse into one entry (best: ATV, then highest score) — the "same song from a different channel" duplicates disappear from the list.
- **Why the modal may still show despite a 100% candidate:** (1) source is itself a version (e.g. `"Song (Live)"`) and the only 100 is a *different* version (marker mismatch) — a 100 with the *same* marker now auto-binds; (2) two distinct eligible candidates tie at 100 and neither carries the source's exact feat identity; (3) a genuine near-tie within 8 points of the winner. These are the correct "human decides" cases — the old false-positive cases (feat credit, duplicate channel) no longer open the modal.

## Resolution endpoints

```text
GET    /api/tracks/{track_id}/resolution            → 200 request row | 404
POST   /api/tracks/{track_id}/resolution            → 202 | 422 INVALID_RESOLUTION
DELETE /api/tracks/{track_id}/resolution            → 204 | 404
POST   /api/tracks/{track_id}/resolution/reopen     → 200 | 409 | 403 | 404 | 503 | 422
POST   /api/tracks/{track_id}/resolution/search     → 200 | 404 | 422 | 503   (NEW — dead-end escape hatch)
```

- **`GET`** returns the active request row (includes `id`, `candidates`, `source_title`, `source_artists`, `source_duration`, `status`, `reason_code`, `created_at`, `expires_at`). 404 when none.
- **`409` always carries YOUR OWN `resolution_id` + `candidates`** (Exchange 38): if you have no stored request for the track yet, the server creates one on the fly (a fresh matching run) instead of returning a dead-end 409 with an empty candidate list. Keep the defensive guard anyway — disable Select when `resolution_id` is null rather than crashing.
- **`POST`** body: `{ "resolution_id": "uuid", "video_id": "candidate_video_id" }` (schema `ResolutionSelection`). Returns the 202 queued shape. `422 INVALID_RESOLUTION` for unknown/expired/cancelled requests or video ids not in the stored candidate list — **never submit an arbitrary YouTube URL or video id**.
- **`DELETE`** (optional query param `resolution_id`) cancels an owned request; nothing downloads.
- **`reopen`** ("report wrong match"): clears the stored source + local files, parks the track in `needs_resolution`, and **flags it so automatic background matching never re-runs** — the track stays unresolved until the user picks a candidate or uploads a file. The server runs a **fresh, non-binding YouTube search of the track's own title** to pre-populate the candidate modal (if YouTube is down, the track is still parked and the modal opens empty — custom search remains available). Returns `{ "status": "needs_resolution", "track_id", "request": <active request row | null> }` — **reopen never returns `queued` anymore**; don't render a "queued" branch for it. `409` while a download is active or for non-Deezer tracks, `403` if the request belongs to another user, `404` if the track isn't found. **Only Deezer-sourced (`dz_…`) tracks support reopen** — hide or disable "report wrong match" for legacy YT/curator tracks. **Disable this action while a download is active** and refresh track state after.
- **`POST …/resolution/search?q=…`** (NEW — the **404 dead-end escape hatch**): only valid when the track is in `unavailable` or `needs_resolution` state. The **server** runs the YouTube Music search for your query (all result types — not just ATV songs, so OMV-only tracks surface too) and stores the raw results as candidates on the resolution request, flipping the track to `needs_resolution`. Returns `200` with `{ "status": "needs_resolution", "track_id", "resolution_id", "candidates": [candidate-shape, …] }` — feed the response straight into the candidate modal you already built, then select via the normal `POST …/resolution`. **Zero hits are not a state change**: an empty `candidates` list returns `status` as the track's current state (`unavailable`/`needs_resolution`) and flips nothing — show a "no results, try another query" empty state and let the user search again. `404` unknown track, `422 CUSTOM_SEARCH_INVALID` when the track isn't unresolved, `503 PROVIDER_UNAVAILABLE` when YouTube is down. **Never send an arbitrary YouTube URL/video id anywhere** — the server decides the candidates; you only pick from them.

### Rate limiting (Exchange 38)

- **Completed / local-disk streams bypass rate limiting entirely** — `GET /api/tracks/stream/{id}` for a track that is `completed` with an audio file on disk never consumes a bucket (the server caches the completed-state probe). Heavy listening / long sessions can no longer 429 on local playback.
- Unresolved / pending tracks still fall under the stream rule (`90/min, burst 40`) because they proxy live audio from YouTube Music.
- Everything else is unchanged (auth, search, download bursts, safety fuse).

## Behavior by feature

### Download / stream

`POST /api/tracks/download/{track_id}` and `GET /api/tracks/stream/{track_id}` now map to the error-code contract above. For streaming:

- `409` → open the candidate modal; **do not start the audio player**.
- `404` → show unavailable state; **do not retry in a loop**.
- `503` → show "provider temporarily unavailable", offer a retry.
- `504` → download already started but slow; show retry/wait controls, not a matching failure.
- After auto-match or manual selection, retry the stream with the canonical `track_id`.

### Favorites & playlists

`POST /api/favorites/{track_id}` and `POST /api/playlists/{id}/tracks` accept a `dz_…` id and now propagate the same `409/404/503` contract — handle those errors on these calls too.

- Do **not** optimistically show a track as added before resolution succeeds.
- If resolution is required, retain the intended destination; complete the add only after a source is selected and queued.
- If the user cancels, leave the favorite/playlist unchanged.

### Albums

`GET /api/albums/{album_id}` — unchanged shape, but **legacy YouTube album tracks now carry `video_type`**: `"ATV"` (audio, has a bound source) or `"OMV"` (video version, **no bound source until the user clicks**). Deezer `dz_<int>` album tracks keep `video_type: null`.

- Render OMV tracks visibly labeled as video versions, still clickable.
- Clicking an OMV track goes through normal strict resolution: auto-match → queues the ATV; ambiguous → `409`; unavailable → `404`. Never a silent video download.

`POST /api/albums/download/{album_id}` → **202 with honest per-track counts** (new shape):

```jsonc
{
  "album": "Discovery",
  "artists": ["Daft Punk"],
  "total_tracks": 12,
  "queued_for_download": 8,
  "already_downloaded": 2,
  "needs_resolution": 1,     // actionable review items — surface them
  "unavailable": 1,          // provider or track unavailable
  "failed": 0
}
```

- Allow the album operation to continue for safe tracks; show unresolved tracks as actionable review items; **do not block the whole album** because one track needs a decision.

### CSV imports

`POST /api/import/csv` → `202 { "job_id", "status": "processing", ... }`; poll `GET /api/import/status/{job_id}`.

Status response (new counters are **derived from the actual pending requests** — trust them):

```jsonc
{
  "job_id": "uuid",
  "status": "processing" | "completed" | "completed_with_review",
  "total": 3,
  "processed": 3,
  "queued": 1,          // rows resolved & queued
  "failed": 0,
  "needs_review": 1,    // rows needing manual selection
  "unavailable": 1,     // provider outage / no source (retryable or dead)
  "failed_tracks": [],
  "review_items": [     // pending resolution requests, one per unresolved row
    {
      "id": "uuid",             // this IS the resolution_id
      "track_id": "dz_..." | null,
      "source_row_key": "2",
      "provider": "deezer" | "youtube_music",
      "reason_code": "DEEZER_SELECTION_REQUIRED" | "YOUTUBE_SELECTION_REQUIRED"
                   | "DEEZER_PROVIDER_UNAVAILABLE" | "YOUTUBE_PROVIDER_UNAVAILABLE" | ...,
      "source_title": "...",
      "source_artists": ["..."],
      "source_duration": 214,
      "candidates": [ candidate-shape, ... ],
      "destination_mode": "favorites" | "playlist"
    }
  ]
}
```

Selecting an import row:

- **Import-specific:** `POST /api/import/resolution/{resolution_id}` body `{ "candidate_id": "..." }` → `202 { "status": "queued", "track_id": "..." }`, or a review item if continuation needs another decision. Also `POST /api/import/resolution/{resolution_id}/retry` to re-run a provider lookup (`YOUTUBE_RETRY_FAILED` etc.).
- **Generic track endpoint (also works):** `POST /api/tracks/{track_id}/resolution` with `{ "resolution_id": "...", "video_id": "..." }` — import requests are delegated internally, so one selection modal can serve both. The job's counters and destination routing update either way.

Render unresolved rows with their candidate list / `resolution_id`, allow resolving later, and show the rest of the import as completed **without guessing**.

## Summary contract table

| Surface | Change | Frontend action |
|---|---|---|
| Tokens in URL | `401`, no fallback | **Migrate to `Authorization: Bearer`** (S-03). |
| `POST /api/tracks/download/{id}`, `GET /api/tracks/stream/{id}` | New `409/404/503` error contract | Build candidate modal + unavailable/provider states (R-01). |
| `download_status` | New values `needs_resolution`, `unavailable` | Render as distinct states; no source → never playable. |
| `GET/POST/DELETE /api/tracks/{id}/resolution` + `/reopen` + `…/resolution/search` | **New endpoints** | Selection modal, cancel, "report wrong match" (Deezer tracks only), custom-search escape hatch for `404 TRACK_UNAVAILABLE`. |
| Favorites/playlists (`POST /api/favorites/{track_id}`, `POST /api/playlists/{id}/tracks`) | Accept `dz_…` ids; propagate `409/404/503` | Handle resolution errors before mutating local state. |
| `GET /api/tracks/{id}` (metadata) | `download_status` may now be `needs_resolution`/`unavailable` | Render those states on track pages, not only in error paths. |
| Album tracks (`GET /api/albums/{id}`) | Legacy YT tracks carry `video_type` `ATV`/`OMV` | Label OMV as video version; click resolves strictly. |
| `POST /api/albums/download/{id}` | Honest counts: `queued_for_download`, `already_downloaded`, `needs_resolution`, `unavailable`, `failed` | Show per-track outcomes; surface review items. |
| Import status | `needs_review`/`unavailable` derived from pending requests; `review_items[]` with `resolution_id` | Render unresolved rows; select via `/api/import/resolution/{id}` (or generic track endpoint). |
| Range requests | Strict; malformed/out-of-range → `416` | Drop client-side `416` retries. |
| Login/refresh | `must_change_password` flag | Route to password-change screen (S-07). |
| `POST /api/auth/change-password` | **New endpoint** | Password-change form (S-07). |

## Full API reference (all endpoints)

Every endpoint the frontend can call, grouped by router. `[new]` = added by the
hybrid-resolution work; `[changed]` = existing endpoint whose contract changed.
Everything is behind `Authorization: Bearer <token>` unless noted.

### Auth — `/api/auth`

| Method | Path | Description |
|---|---|---|
| POST | `/api/auth/register` | Create a user (username + password). `201`. |
| POST | `/api/auth/login` | `[changed]` Multi-device: login mints a NEW device session — **it no longer kicks other logged-in devices**. Response unchanged (access + refresh token, `must_change_password` flag). `200`. |
| POST | `/api/auth/refresh` | `[changed]` Rotates the refresh token per-device; response unchanged. `200`. |
| POST | `/api/auth/change-password` | `[new]` S-07: rotate password (`{current_password, new_password}`); **revokes ALL devices**, forces re-login. `200`/`401`/`400`. |
| POST | `/api/auth/logout` | `[changed]` Revokes **only the calling device** (bearer = the refresh token); other devices stay logged in. `204`. |

### Search — `/api/search`

| Method | Path | Description |
|---|---|---|
| GET | `/api/search?q=…` | Local + Deezer fan-out search; envelope with `remote_source`, per-category results. `200`. |

### Tracks — `/api/tracks`

| Method | Path | Description |
|---|---|---|
| GET | `/api/tracks` | List locally downloaded tracks (`download_status = completed`). `200`. |
| GET | `/api/tracks/stream/{track_id}` | Stream audio with Range support; auto-downloads on miss. Resolution contract: `409`/`404`/`503`/`422`/`504`. `200`/`206`. |
| GET | `/api/tracks/cover/{track_id}` | Album cover art for a track. `200`/`404`. |
| POST | `/api/tracks/download/{track_id}` | `[changed]` Queue a download; accepts `dz_…` ids; resolution contract `202`/`409`/`404`/`503`/`422`. |
| GET | `/api/tracks/{track_id}` | Full metadata (title, artists, lyrics, URLs); `download_status` may be `needs_resolution`/`unavailable`. `200`/`404`. |
| GET | `/api/tracks/{track_id}/album` | Resolve the album browse id for a track. `200`/`404`/`503`. |
| GET | `/api/tracks/{track_id}/discovery?limit=15` | `[new]` Radio discovery — Deezer-only. Returns `{seed, reason, queue[]}`; each queue item has `track_id, title, artists, album, duration_seconds, cover_url, stream_url, reason` (`same_album` \| `same_artist` \| `similar_artist`). Empty queue + `reason` (`seed_not_found` / `seed_without_deezer_identity`) for non-Deezer seeds. `200`. |
| GET | `/api/tracks/{track_id}/related` | Related songs/sections from YouTube. `200`/`404`. |
| GET | `/api/tracks/{track_id}/resolution` | `[new]` Active resolution request (candidates + source info). `200`/`404`. |
| POST | `/api/tracks/{track_id}/resolution` | `[new]` Select a stored candidate `{resolution_id, video_id}` → queues download. `202`/`422 INVALID_RESOLUTION`. |
| DELETE | `/api/tracks/{track_id}/resolution` | `[new]` Cancel the active resolution request; nothing downloads. `204`/`404`. |
| POST | `/api/tracks/{track_id}/resolution/reopen` | `[new]` "Report wrong match": clear source + local files, park track in `needs_resolution` with auto-match bypassed (`skip_automatch`), pre-populate candidates via a fresh non-binding search. Deezer (`dz_…`) tracks only. `200`/`409`/`403`/`404`/`503`/`422`. |
| POST | `/api/tracks/{track_id}/resolution/search?q=…` | `[new]` Custom YouTube search for `unavailable`/`needs_resolution` tracks; server stores results as candidates and flips the track to `needs_resolution`. `200`/`404`/`422 CUSTOM_SEARCH_INVALID`/`503`. |

### Albums — `/api/albums`

| Method | Path | Description |
|---|---|---|
| GET | `/api/albums/local` | Curator-created albums. `200`. |
| GET | `/api/albums/{album_id}` | `[changed]` Album detail — polymorphic (`dz_…` / `local_album_…` / `MPREb_…`); Deezer path JSONB-cached; legacy YT tracks carry `video_type` `ATV`/`OMV`; per-track `is_downloaded` + `downloaded_count`. `?refresh=true` bypasses cache. `200`/`503`/`500`. |
| POST | `/api/albums/download/{album_id}` | `[changed]` Bulk-queue album; returns honest counts (`total_tracks`, `queued_for_download`, `already_downloaded`, `needs_resolution`, `unavailable`, `failed`). `202`. |
| GET | `/api/albums/cover/{album_id}` | Album cover (uploaded or auto-cached; lazy fetch). `200`/`404`. |

### Artists — `/api/artists`

| Method | Path | Description |
|---|---|---|
| GET | `/api/artists/local` | Curator-created artists. `200`. |
| GET | `/api/artists/by-name/{name}` | Artist lookup by exact name. `200`/`404`. |
| GET | `/api/artists/directory` | Artists directory (paginated, `?limit=`). `200`. |
| GET | `/api/artists/{channel_id}` | `[changed]` Artist detail — polymorphic (`dz_…` / `UC…` / `local_artist_…`); Deezer path is stateless fan-out (base + albums + top songs). `200`/`503`. |
| GET | `/api/artists/local/{artist_id}` | Single curator-created artist detail. `200`/`404`. |
| GET | `/api/artists/cover/{artist_id}` | `[changed]` Artist photo — local file `200`; **no local file → `302` redirect to the stored CDN avatar URL** (Deezer/YouTube rows), lazily fetching the Deezer picture once for legacy rows; `404` when nothing resolvable. |

### Library (favorites / playlists / history) — `/api`

| Method | Path | Description |
|---|---|---|
| GET | `/api/favorites` | User's favorites. `200`. |
| GET | `/api/favorites/{track_id}` | Is this track favorited? `200`. |
| POST | `/api/favorites/{track_id}` | `[changed]` Favorite a track; accepts `dz_…` ids; resolution contract `201`/`409`/`404`/`503`. |
| DELETE | `/api/favorites/{track_id}` | Remove from favorites. `200`. |
| GET | `/api/playlists` | User's playlists. `200`. |
| POST | `/api/playlists` | Create a playlist. `201`. |
| GET | `/api/playlists/{playlist_id}` | `[changed]` Playlist detail — polymorphic (`dz_…` / int); Deezer path stateless with per-track status + `downloaded_count`. `200`/`404`/`503`. |
| PUT | `/api/playlists/{playlist_id}` | Update a local playlist. `200`. |
| DELETE | `/api/playlists/{playlist_id}` | Delete a local playlist. `200`. |
| POST | `/api/playlists/{playlist_id}/cover` | Upload playlist cover. `200`. |
| GET | `/api/playlists/{playlist_id}/cover` | Serve playlist cover. `200`/`404`. |
| GET | `/api/playlists/{playlist_id}/tracks` | List a playlist's tracks. `200`. |
| POST | `/api/playlists/{playlist_id}/tracks` | `[changed]` Add track; accepts `dz_…` ids; resolution contract `201`/`409`/`404`/`503`. |
| DELETE | `/api/playlists/{playlist_id}/tracks` | Remove a track from a playlist. `200`. |
| PUT | `/api/playlists/{playlist_id}/tracks/reorder` | Reorder playlist tracks. `200`. |
| POST | `/api/history` | Record a listen. `201`. |
| GET | `/api/history` | User's listening history. `200`. |
| GET | `/api/history/statistics` | Listening statistics. `200`. |

### Player (radio/queue) — `/api/player` `[new section]`

Server-side "now playing" + the queue, with **two modes** selected via `queue_mode`:

- `radio` (default) — the queue is **server-owned**. When it drops below 3 tracks, the backend
  appends a fresh Deezer-discovery batch from the current track (refill-when-low). A brand-new
  `current_track_id` regenerates the queue as fresh radio from that seed.
- `context` — the queue is **frontend-owned** (playlist / favorites / album). Load it by
  sending `queue_mode: "context"` together with `queue` (the tracks still to come — the
  current track is NOT included). Discovery **never runs**: the queue only pops (head start /
  `next`), and `POST /next` returns `404` when it runs out — the stop signal. A track change
  never injects or regenerates anything.

| Method | Path | Description |
|---|---|---|
| GET | `/api/player/state` | Current state + queue + history. Returns `{device_id, current_track_id, position_ms, is_playing, queue[], queue_count, queue_mode, history[], history_count, refilled}` (defaults when nothing played yet: `queue_mode: "radio"`, empty history). `200`. |
| PUT | `/api/player/state` | Partial heartbeat. Fields: `{device_id?, current_track_id?, position_ms?, is_playing?, queue_mode?, queue?}` — omitted fields are kept (a position-only heartbeat never wipes the queue or the mode). **Track-change rule (radio):** new `current_track_id` was the queue's head → it is popped (advance); any other new track → queue regenerates as fresh radio. **Track-change rule (context):** head starts → popped; any other track → queue unchanged (re-send `queue` to re-order). `200`. |
| GET | `/api/player/queue` | The queue only: `{queue[], queue_count}`. `200`. |
| GET | `/api/player/devices` | `[new]` Device picker data: every device with a live SSE connection (from `GET /events`) plus the session owner even when its socket is closed but its heartbeat is fresh. Returns `{devices: [{device_id, device_name, is_player, is_alive}]}`, owner first. `200`. |
| POST | `/api/player/next` | Advance: current = queued head, queue shifts, refill applied (radio only). `200`/`404` — in `context`, `404` once the queue drains (stop signal). |
| POST | `/api/player/previous` | Step back one track (Spotify-style): the previous track becomes current **with its saved position**, and the skipped track is re-inserted at the queue head so `next` replays it. `200`/`404` when the history is empty — disable the back button (`history_count == 0`). |

**Backward playback (Exchange 37):** the backend keeps a per-session **history stack** (max
50 entries `{track_id, position_ms}`). `next` and skipping-by-heartbeat record the finished
track; `previous` pops it back with its position. History resets when a fresh context queue is
loaded (`queue` + `queue_mode` together) and when a brand-new radio seed starts. ⚠️ Re-inserted
queue items carry **only `track_id`** (no title/artists/cover) — hydrate them via
`GET /api/tracks/{id}` before rendering; every other queue item has full metadata.

Suggested frontend flow — radio: on track start → `PUT /api/player/state` with the new
`current_track_id` (the backend decides head-advance vs fresh radio); on skip → `POST
/api/player/next` and play the returned `current_track_id`; render `queue` from any state
response (show a "reason" label: `same_album` = from the same album, `same_artist` = more from
the artist, `similar_artist` = radio). Playlist/favorites/album: send the playlist tracks once
with `queue_mode: "context"` + `queue`; the backend then never touches the queue, and `next`
404s at the end so the player stops instead of inventing tracks. Back button: enable when
`history_count > 0`, call `POST /api/player/previous`, play the returned `current_track_id`
(position restored server-side). Multi-device: any logged-in device reads the same state;
a `context` load or a `previous` from one device applies to all.

**Device picker (Exchange 46 + 47 — zero polling):** pass `device_id` **and** `device_name` as
query params on `GET /api/player/events` — the name labels the connection for
`GET /api/player/devices`. `is_player` marks the current owner, `is_alive` whether it's
reachable right now (SSE open, or owner with a fresh heartbeat). Taking over still goes through
`POST /api/player/takeover` with `force: true` — the picker is read-only.

**The SSE stream now carries a typed `devices` event — you never need to poll `/devices`:**

- **On connect:** the joining device appears on every client's picker via a `devices` event.
- **On disconnect:** the leaving device disappears from every surviving client's picker via a
  `devices` event (the OWNER persists in the picker while its heartbeat is fresh — by design).
- **On stale-owner release:** ~`OWNER_HEARTBEAT_TTL_SECONDS` (30s) after a real app close (SSE
  gone **and** heartbeat expired — a flaky connection keeps heartbeating and is never released),
  the backend frees the session and pushes **both** a `state` snapshot (`device_id: null`,
  `device_name: null`) **and** a fresh `devices` event to every open connection. The track,
  position and queues stay — the next claimer resumes where the closed app left off.

Wire format (event type `devices`):
```
event: devices
data: { "devices": [ { "device_id", "device_name", "is_player", "is_alive" }, ... ] }
```
Keep `GET /api/player/devices` as the initial-fetch / reconnect fallback only. ⚠️ **In state
snapshots, `is_player` is relative to the publishing device — derive your own role with
`myDeviceId == snapshot.device_id`, never trust the pushed flag alone** (e.g. a `next` from the
owner broadcasts `is_player: false` to everyone, including the owner).

### Imports — `/api/import`

| Method | Path | Description |
|---|---|---|
| POST | `/api/import/csv` | Start a Spotify-CSV import; returns `{job_id, status_url}`. `202`. |
| GET | `/api/import/status/{job_id}` | `[changed]` Job progress with derived `needs_review`/`unavailable` + `review_items[]` (pending requests, each with `resolution_id`/`candidates`). `200`/`404`. |
| POST | `/api/import/resolution/{resolution_id}` | Select an import candidate `{candidate_id}`; queues + routes to destination. `202`/`422`. |
| POST | `/api/import/resolution/{resolution_id}/retry` | Re-run a provider lookup for a collected row. `202`/`422`. |

### Admin — `/api/admin`

| Method | Path | Description |
|---|---|---|
| GET | `/api/admin/users/pending` | Pending-approval users. `200`. |
| GET | `/api/admin/users` | All users. `200`. |
| POST | `/api/admin/users/{username}/approve` | Approve a user. `200`. |
| POST | `/api/admin/curator/{username}` | Promote a user to curator. `200`. |
| GET | `/api/admin/stats` | Library statistics (status counts, disk, users). `200`. |
| GET | `/api/admin/orphans` | Orphaned files/tracks. `200`. |
| POST | `/api/admin/retry-failed` | Retry failed downloads (excludes `needs_resolution`/`unavailable`). `200`. |
| DELETE | `/api/admin/tracks/{track_id}` | Delete a track + its files. `200`. |

### Curator — `/api/curator`

| Method | Path | Description |
|---|---|---|
| PUT | `/api/curator/tracks/{track_id}` | Update track metadata (title, artist ids, album, lyrics). `200`. |
| POST | `/api/curator/tracks/{track_id}/cover` | Upload track cover art. `200`. |
| POST | `/api/curator/tracks/upload` | `[changed]` Upload a local audio track — optional `target_track_id` form field binds the file to an EXISTING track stuck in `unavailable`/`needs_resolution`/`discovered` (fulfills it with no YouTube source; `yt_id` stays null, `is_local_upload=true`, open resolution requests closed). **The track's Deezer metadata is preserved** — album, artists, and the HD Deezer cover survive the bind (album_id + artists junction are persisted at resolution-store time; the album stub keeps the cover resolvable). Response now includes `album` + `cover_url` (`/api/tracks/cover/{id}` when a cover is available). Curators/admins only. `201`/`404`/`409`/`400`. |
| POST | `/api/curator/albums` | Create a local (curator) album. `201`. |
| POST | `/api/curator/albums/{album_id}/cover` | Upload album cover. `200`. |
| POST | `/api/curator/artists` | Create a local (curator) artist. `201`. |
| POST | `/api/curator/artists/{artist_id}/cover` | Upload artist cover. `200`. |

---

## How to test (end-to-end)

These flows assume header auth (`Authorization: Bearer <token>`). Use a track that is genuinely ambiguous/unavailable on YouTube to force the branches, or ask the backend team for fixture ids.

1. **Auto-match happy path:** `POST /api/tracks/download/dz_<id>` → `202` queued shape → poll `GET /api/tracks/{id}` metadata until `download_status: "completed"` → stream works. (The metadata endpoint is also where `needs_resolution`/`unavailable` states surface after a 409/404 — poll it to refresh.)
2. **Ambiguous → select:** `POST /api/tracks/download/dz_<id>` → `409` with non-empty `candidates` → open modal → `POST /api/tracks/dz_<id>/resolution` with a stored candidate → `202` → track completes. Cancel variant: `DELETE /api/tracks/dz_<id>/resolution` → `204`, track stays unresolved, nothing downloaded.
3. **Invalid selection:** POST with a video id not in the candidate list → `422 INVALID_RESOLUTION`, nothing queued.
4. **Unavailable:** a track with no plausible match → `404 TRACK_UNAVAILABLE`; no download, no retry loop in UI.
5. **Provider down:** stop/disable Deezer or YouTube → `503 PROVIDER_UNAVAILABLE`; UI offers retry, not "song missing".
6. **Reopen (manual, no re-queue):** on a wrong source, `POST /api/tracks/dz_<id>/resolution/reopen` → `200` `{status: needs_resolution}`; the track's `yt_id` and local audio are cleared and it **stays unresolved — the background worker must not re-claim it** (previously it re-auto-matched the same video within ~1.5s and broke custom search). Assert: `GET /api/tracks/{id}` shows `download_status: needs_resolution`, the modal is pre-populated (or empty when YouTube is down — custom search still works), selecting a candidate or uploading a file lifts the guard and queues normally. Disabled while downloading.
7. **Album download counts:** download an album containing a mix of queued/already-downloaded/unresolvable tracks → assert the five counters sum to `≤ total_tracks` (equal when every track has an id); unresolved tracks appear as review items, album not blocked.
8. **OMV label:** open a legacy `MPREb_…` album → OMV tracks render with `video_type: "OMV"` and `download_status: "discovered"`; clicking one never downloads the video directly — it strict-resolves (auto-match → ATV queues; else `409`/`404`).
9. **Import review flow:** upload a CSV with rows that auto-match, are ambiguous, and are provider-unavailable → poll status → `queued` + `needs_review` + `unavailable` sum to `total`; select an ambiguous row via `/api/import/resolution/{id}` → it moves to queued and the row disappears from `review_items`; selecting the same row a second time fails cleanly (no double-count).
10. **Auth smoke:** DevTools Network — tokens only in headers (S-03); admin first login → `must_change_password: true` → 403 elsewhere → `/change-password` → re-login → flag false (S-07).
11. **Custom search (dead-end escape):** on a `404 TRACK_UNAVAILABLE` track, call `POST /api/tracks/dz_<id>/resolution/search?q=<query>` → `200` with `candidates` + `resolution_id` → open the same modal → select → `202` queued. `422` when the track is already downloaded; `503` when YouTube is down.
12. **Curator upload binding:** as a curator, `POST /api/curator/tracks/upload` with `target_track_id=dz_<unavailable-id>` + audio file → `201`; the track flips to `completed`, streams immediately, and any open resolution request for it disappears from review lists. **Assert metadata preserved:** the response carries `title`/`artists`/`album`/`cover_url` matching the Deezer source (not YouTube's), and `GET /api/tracks/{id}` still returns the Deezer title + artist junction + album link after the bind.
13. **Artist cover (no more 404s):** `GET /api/search?q=<artist>&remote=false` → local `dz_…`/`UC…` artists carry `avatar_art` as a CDN URL (or serving endpoint for local artists) — never `null` when an avatar exists; `GET /api/artists/{id}/cover` follows with `302` to the avatar when no local file is stored (legacy `dz_…` rows self-heal on first hit via a one-time Deezer fetch).

---

## Things to leave alone on both sides

- **S-06 — slide-on-refresh.** Keep the rolling token + grace-window model. Do not introduce idle expiration, max-session-lifetime, or per-time-window expiry.

---

## Final ask

1. Confirm the **S-03 refactor** (token migration to headers).
2. Implement the **S-07 password-change flow**.
3. Implement the **R-01 resolution UX** (candidate modal, unavailable/provider states, album review items, import review rows, "report wrong match" via reopen) per the contracts above.
4. Run the **end-to-end test flows** in "How to test" and report any divergence from the documented status codes / shapes.
5. Ping us if (a) the contract table changes, or (b) you find a token-in-URL surface or a resolution edge we both missed.
