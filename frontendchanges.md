# Frontend Changes — Deezer-Canonical Track Identity

## Overview

The backend now treats Deezer as the canonical catalog source.

For Deezer-backed tracks:

```text
tracks.id  = canonical Deezer track ID
tracks.yt_id = optional YouTube Music source ID
```

Example:

```json
{
  "id": "dz_3135551",
  "yt_id": "YT_resolved_source_id",
  "title": "One More Time"
}
```

The frontend must use the Deezer ID for application identity and navigation. The YouTube ID is an internal backend implementation detail used for downloading audio and lyrics.

---

## 1. Deezer IDs are strings with a `dz_` prefix

Deezer browse and search entities use string IDs:

```text
dz_3135551       // track
dz_302127        // album
dz_27            // artist
dz_90819         // playlist
```

Do not parse these IDs as integers. Preserve them as strings when:

- Storing them in frontend models or state.
- Building URLs.
- Sending them in request bodies.
- Comparing IDs.
- Using them as list keys.

Example:

```ts
const trackId = "dz_3135551";
await api.post(`/api/favorites/${trackId}`);
```

---

## 2. Track identity fields

The following fields have distinct meanings:

| Field | Meaning | Frontend usage |
|---|---|---|
| `id` | Canonical entity ID. For Deezer tracks this is `dz_<id>`. | Primary identity for browse results and local catalog entities. |
| `track_id` | Explicit canonical local/database track ID in local-library responses. | Prefer this when present in favorites, playlists, history, and download responses. |
| `video_id` | Backward-compatible response field. It now represents the canonical track ID in local-library/download responses, not necessarily a YouTube ID. | Keep reading it for compatibility, but do not assume it is a YouTube ID. |
| `yt_id` | YouTube Music source ID used internally for download and lyrics. | Displaying or persisting it in frontend state is not necessary. Never use it as the canonical track identity. |

Recommended frontend normalization:

```ts
type TrackIdentity = {
  id: string;
  yt_id?: string | null;
};

function getCanonicalTrackId(track: any): string | null {
  return track.track_id ?? track.id ?? track.video_id ?? null;
}
```

For a Deezer browse result before download, `video_id` may be `null`:

```json
{
  "id": "dz_3135551",
  "video_id": null,
  "yt_id": null,
  "title": "One More Time",
  "is_downloaded": false,
  "download_status": null
}
```

This is expected. Use `id`, not `video_id`, for the click/download action.

---

## 3. Deezer search results

Deezer search results now expose prefixed IDs. A track result is shaped like:

```json
{
  "id": "dz_3135551",
  "title": "One More Time",
  "artist_name": "Daft Punk",
  "artist_id": "dz_27",
  "album_id": "dz_302127",
  "cover_art": "https://...",
  "is_downloaded": false
}
```

Use:

- `id` as the track ID.
- `artist_id` to navigate to the artist.
- `album_id` to navigate to the album.
- `cover_art` for the initial remote artwork.

Do not expect numeric Deezer IDs in the frontend anymore.

---

## 4. Deezer album and playlist tracklists

Browse-time track entries use the canonical Deezer ID:

```json
{
  "id": "dz_3135551",
  "title": "One More Time",
  "artist_name": "Daft Punk",
  "artist_id": "dz_27",
  "album_id": "dz_302127",
  "duration": 320,
  "duration_seconds": 320,
  "video_id": null,
  "is_downloaded": false,
  "download_status": null,
  "preview_url": "https://..."
}
```

The backend may persist a metadata-only row when a Deezer album is browsed. This row has:

```text
id = dz_<track_id>
yt_id = null
download_status = discovered
```

Deezer playlist browsing is currently stateless and does not seed local track rows just by opening a playlist.

That does not mean the audio is available locally. Use `download_status` and `is_downloaded` to determine availability.

Suggested UI state mapping:

| `download_status` | `is_downloaded` | Suggested UI |
|---|---:|---|
| `null` | `false` | Download/play action available. |
| `discovered` | `false` | Track is known to the backend but has not been downloaded. |
| `pending` | `false` | Download queued. |
| `downloading` | `false` | Download in progress. |
| `completed` | `true` | Available locally / streamable. |
| `failed` | `false` | Show retry action. |

---

## 5. Downloading a track

Endpoint:

```http
POST /api/tracks/download/{track_id}
```

For a Deezer track, send the canonical Deezer ID:

```http
POST /api/tracks/download/dz_3135551
```

Do not send the resolved YouTube ID from the frontend.

A newly queued response looks like:

```json
{
  "status": "queued",
  "track_id": "dz_3135551",
  "video_id": "dz_3135551",
  "yt_id": "YT_resolved_source_id",
  "title": "One More Time",
  "message": "Download queued. YouTube download takes < 1 second.",
  "stream_url": "/api/tracks/stream/dz_3135551"
}
```

Other valid responses include:

- `status: "success"` when the track is already completed.
- `status: "queued"` with an "already in download queue" message when it is pending/downloading.

The backend resolves and stores the YouTube source. On later requests, a known canonical row with a stored `yt_id` should not require another Deezer or YTMusic resolution call.

A failed resolution returns HTTP `422`:

```json
{
  "detail": "Could not resolve browse track to a YouTube version: ..."
}
```

The frontend should show a retry or unavailable state rather than treating this as a generic server failure.

---

## 6. Streaming

Endpoint:

```http
GET /api/tracks/stream/{track_id}
```

Use the canonical ID:

```text
/api/tracks/stream/dz_3135551
```

Use the backend-provided `stream_url` whenever possible.

Do not build the stream URL with `yt_id`:

```text
Incorrect: /api/tracks/stream/YT_resolved_source_id
Correct:   /api/tracks/stream/dz_3135551
```

The backend uses the canonical ID to locate the local file and the stored YouTube ID to download it when necessary.

The stream endpoint supports HTTP range requests, so existing audio-player range behavior should remain unchanged.

---

## 7. Track metadata and covers

Track metadata endpoint:

```http
GET /api/tracks/{track_id}
```

Cover endpoint:

```http
GET /api/tracks/cover/{track_id}
```

Both endpoints should receive the canonical ID:

```text
/api/tracks/dz_3135551
/api/tracks/cover/dz_3135551
```

A metadata response may include:

```json
{
  "track_id": "dz_3135551",
  "video_id": "dz_3135551",
  "yt_id": "YT_resolved_source_id",
  "title": "One More Time",
  "download_status": "completed",
  "stream_url": "/api/tracks/stream/dz_3135551",
  "cover_url": "/api/tracks/cover/dz_3135551"
}
```

---

## 8. Favorites

Add a favorite:

```http
POST /api/favorites/{track_id}
```

Remove a favorite:

```http
DELETE /api/favorites/{track_id}
```

Check favorite status:

```http
GET /api/favorites/{track_id}
```

For Deezer tracks, `{track_id}` must be the `dz_*` ID.

Example:

```http
POST /api/favorites/dz_3135551
```

The add response uses the canonical ID:

```json
{
  "favorite_id": "dz_3135551"
}
```

Favorite list items include canonical identity fields and canonical stream/cover URLs:

```json
{
  "track_id": "dz_3135551",
  "video_id": "dz_3135551",
  "yt_id": "YT_resolved_source_id",
  "title": "One More Time",
  "stream_url": "/api/tracks/stream/dz_3135551",
  "cover_url": "/api/tracks/cover/dz_3135551"
}
```

---

## 9. Playlists

Add a track:

```http
POST /api/playlists/{playlist_id}/tracks
Content-Type: application/json

{
  "track_id": "dz_3135551"
}
```

Remove a track:

```http
DELETE /api/playlists/{playlist_id}/tracks
Content-Type: application/json

{
  "track_id": "dz_3135551"
}
```

Reorder tracks with canonical IDs:

```json
{
  "new_order": [
    "dz_3135551",
    "dz_3135552"
  ]
}
```

Playlist track list entries include:

```json
{
  "track_id": "dz_3135551",
  "video_id": "dz_3135551",
  "yt_id": "YT_resolved_source_id",
  "title": "One More Time",
  "download_status": "completed",
  "stream_url": "/api/tracks/stream/dz_3135551",
  "cover_url": "/api/tracks/cover/dz_3135551"
}
```

The Deezer browse playlist endpoint remains read-only:

```http
GET /api/playlists/dz_90819
```

The numeric/local playlist mutation endpoints continue to use integer playlist IDs.

---

## 10. Listening history

Record a listen using the canonical track ID:

```http
POST /api/history
Content-Type: application/json

{
  "track_id": "dz_3135551"
}
```

History responses use canonical IDs for track navigation and streaming:

```json
{
  "track_id": "dz_3135551",
  "video_id": "dz_3135551",
  "yt_id": "YT_resolved_source_id",
  "stream_url": "/api/tracks/stream/dz_3135551",
  "cover_url": "/api/tracks/cover/dz_3135551"
}
```

---

## 11. Existing YouTube and curator tracks

Legacy tracks remain supported:

- YouTube-backed tracks retain their existing ID behavior.
- Curator uploads retain their `local_*` IDs.
- These tracks may have `yt_id` equal to their legacy source ID or may use the legacy ID as the source fallback.

The generic `GET /api/tracks` local-library response primarily exposes the database row's `id`; use that as the canonical ID there. The explicit `track_id` field is present in favorites, playlists, history, metadata, and download responses.

The frontend should not infer the source provider solely from whether `yt_id` exists. Use the ID prefix when provider-specific behavior is needed:

```ts
function getTrackSource(id: string): "deezer" | "local" | "legacy" {
  if (id.startsWith("dz_")) return "deezer";
  if (id.startsWith("local_")) return "local";
  return "legacy";
}
```

---

## 12. Recommended frontend model updates

A track model should allow nullable source metadata:

```ts
export type Track = {
  id?: string | null;
  track_id?: string | null;
  video_id?: string | null;
  yt_id?: string | null;
  title: string;
  artists?: string[];
  artist_name?: string | null;
  album?: string | null;
  album_id?: string | null;
  duration?: number | null;
  duration_seconds?: number | null;
  is_downloaded?: boolean;
  download_status?:
    | "pending"
    | "downloading"
    | "completed"
    | "failed"
    | "discovered"
    | null;
  stream_url?: string | null;
  cover_url?: string | null;
  cover_art?: string | null;
  preview_url?: string | null;
};
```

Centralize identity extraction instead of reading `video_id` throughout the UI:

```ts
export function canonicalTrackId(track: Track): string | null {
  return track.track_id ?? track.id ?? track.video_id ?? null;
}
```

Centralize URLs as well:

```ts
export function trackStreamUrl(track: Track, apiBase = ""): string | null {
  if (track.stream_url) return track.stream_url;
  const id = canonicalTrackId(track);
  return id ? `${apiBase}/api/tracks/stream/${encodeURIComponent(id)}` : null;
}

export function trackCoverUrl(track: Track, apiBase = ""): string | null {
  if (track.cover_url) return track.cover_url;
  const id = canonicalTrackId(track);
  return id ? `${apiBase}/api/tracks/cover/${encodeURIComponent(id)}` : null;
}
```

---

## 13. Do not use `yt_id` for these operations

Never use `yt_id` as the identifier for:

- React/Flutter list keys.
- Favorite state keys.
- Playlist membership keys.
- History records.
- Stream URLs.
- Cover URLs.
- Track detail routes.
- Download endpoint paths.
- Deezer track equality checks.

`yt_id` is only the backend's YouTube source reference.

---

## 14. Frontend verification checklist

Test the following flows with a Deezer track such as `dz_3135551`:

- [ ] Deezer search result renders with a string `dz_*` ID.
- [ ] Opening a Deezer album uses `/api/albums/dz_<id>`. Note: the current album router still has a YouTube Music availability guard, so this endpoint may return `503` when YouTube Music is unavailable even if Deezer is enabled; this backend guard should be removed or made Deezer-aware.
- [ ] Opening a Deezer artist uses `/api/artists/dz_<id>`.
- [ ] Opening a Deezer playlist uses `/api/playlists/dz_<id>`.
- [ ] A browse track with `video_id: null` remains clickable.
- [ ] Download sends `POST /api/tracks/download/dz_<track_id>`.
- [ ] Download response uses the canonical ID in `track_id`, `video_id`, and `stream_url`.
- [ ] Player requests `/api/tracks/stream/dz_<track_id>`.
- [ ] Cover requests use `/api/tracks/cover/dz_<track_id>`.
- [ ] Adding to favorites sends the `dz_*` ID.
- [ ] Adding to a playlist sends `{ "track_id": "dz_*" }`.
- [ ] Recording history sends `{ "track_id": "dz_*" }`.
- [ ] A second click does not require the frontend to know the YouTube ID.
- [ ] `discovered`, `pending`, `downloading`, `completed`, and `failed` states render distinctly.
- [ ] Legacy YouTube and curator tracks still play correctly.
- [ ] IDs are URL-encoded when interpolated into paths.

---

## 15. Backend coordination note

The backend should be tested end-to-end with the frontend after dependencies are installed. In particular, verify that Deezer album requests are not incorrectly blocked by a YouTube Music availability guard when YouTube is unavailable but Deezer is enabled.
