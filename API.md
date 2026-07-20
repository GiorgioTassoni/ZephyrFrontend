# Zephyr API Reference

Self-hosted Spotify replacement backend. All API endpoints require authentication via JWT Bearer token (except registration).

**Base URL**: `http://<host>:8000`

---

## Authentication

### POST /api/auth/register

Create a new user account. The account will need admin approval before use.

**Request** (JSON):
```json
{
  "username": "mario",
  "password": "securepassword123"
}
```

**Response** (201):
```json
{
  "status": "success",
  "message": "User created successfully, wait for an admin to approve your account"
}
```

### POST /api/auth/login

Login and receive an **access + refresh token pair**. The access token (a short-lived JWT) is used for `Authorization: Bearer <token>` on all subsequent requests. The refresh token is opaque and used **only** by `/api/auth/refresh`.

**Request** (form-urlencoded):
```
username=mario&password=securepassword123
```

**Response** (200):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "9f4a2b1c8d...64 hex chars",
  "token_type": "bearer",
  "expires_in": 900,
  "role": "user | curator | admin",
  "is_approved": true
}
```

- `access_token`: HS256 JWT with claims `{sub, session, iat, jti, exp}`. Lifetime: 15 minutes.
- `refresh_token`: 256-bit cryptographically-random hex (NOT a JWT). Lifetime: 14 days. Store it; you'll need it to refresh.
- `expires_in`: seconds until the access token expires.

### POST /api/auth/refresh

Rotate the refresh token and mint a new access + refresh pair. **Use the refresh token in `Authorization: Bearer <refresh_token>`, not the access token** — the refresh token alone IS the proof of identity for this call.

**Request**: no body. Authorization header carries the current refresh token.

**Response** (200):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...new...",
  "refresh_token": "1c2d3e4f...new 64 hex chars",
  "token_type": "bearer",
  "expires_in": 900,
  "role": "user | curator | admin",
  "is_approved": true
}
```

**Rotation invariants** (enforced server-side):

| Condition | Server behavior |
|---|---|
| Presented hash matches current `refresh_token_hash` | Rotate, demote old current into a 60-second grace window |
| Presented hash matches `previous_refresh_token_hash` AND grace not expired | Rotate, consume grace (single-flight / network-retry safety) |
| Neither | **401** — caller should re-login |

The absolute session lifetime is capped at 14 days (configurable) regardless of refresh activity. After 14 days the user must log in again.

> **Frontend contract**: store both `access_token` and `refresh_token`. Single-flight concurrent refresh calls (dedupe to one shared in-flight promise). For multi-tab apps, coordinate via `BroadcastChannel` so the second tab inherits the new pair instead of racing — otherwise one tab will lose the race and see a spurious 401, requiring a re-login there.

### POST /api/auth/logout

End the current session family. Wipes access-token fingerprint, the current refresh token, AND any token in the grace window. Idempotent: a subsequent call with an unknown token still returns 204.

**Request**: no body. Authorization header carries the **refresh token** (proof of full session control).

**Response**: 204 No Content.

After `/logout`, all access tokens issued during this session family become invalid because `users.active_session` is set to NULL. The user must log in again.

---

## Search

### GET /api/search?q={query}

Search for songs, albums, artists, playlists, and videos.

**Local-first, YouTube fallback**: the search first looks in your local library
(0 API calls). If local results are found, they are returned immediately with
`has_remote: true`. To also fetch results from YouTube Music, add `?remote=true`.
If no local results exist, the search automatically falls back to YouTube Music.

**Parameters**:
- `q` (required): search query string
- `remote` (optional, default `false`): force search on YouTube Music even if local results exist

**Response** (200) — local only (no API call):
```json
{
  "status": "success",
  "query": "nirvana",
  "has_remote": true,
  "summary": {
    "local_tracks": 3,
    "albums_count": 1,
    "artists_count": 1,
    "playlists_count": 1
  },
  "results": {
    "tracks": [
      {
        "video_id": "hTWKbfoikeg",
        "title": "Smells Like Teen Spirit",
        "artists": "Nirvana",
        "is_downloaded": true,
        "download_status": "completed"
      }
    ],
    "albums": [
      {
        "id": "local_album_a1b2c3",
        "name": "Nevermind (Local Edition)",
        "artists": ["Nirvana"],
        "year": 1991,
        "track_count": 12,
        "cover_url": "/api/albums/cover/local_album_a1b2c3",
        "is_local": true
      }
    ],
    "artists": [
      {
        "id": "local_artist_d4e5f6",
        "name": "Nirvana",
        "bio": "Legendary grunge band",
        "cover_path": "/data/thumbnails/local_artist_d4e5f6.jpg",
        "is_local": true
      }
    ],
    "playlists": [
      {
        "id": 5,
        "name": "Nirvana Unplugged",
        "description": "A collection of unplugged tracks",
        "is_public": true,
        "owner_name": "kurt_cobain",
        "cover_url": "/api/playlists/5/cover"
      }
    ]
  }
}
```

**Response** (200) — YouTube results (with `?remote=true` or no local matches):
```json
{
  "status": "success",
  "query": "nirvana",
  "has_remote": false,
  "summary": {
    "local_tracks": 3,
    "tracks_count": 10,
    "albums_count": 5,
    "artists_count": 3,
    "videos_count": 2,
    "playlists_count": 1
  },
  "results": {
    "tracks": [
      {
        "video_id": "hTWKbfoikeg",
        "title": "Smells Like Teen Spirit",
        "artists": "Nirvana",
        "is_downloaded": true,
        "download_status": "completed"
      },
      {
        "video_id": "E6SbPv1Fu80",
        "title": "In Bloom",
        "artists": "Nirvana",
        "is_downloaded": false
      }
    ],
    "albums": [
      {
        "id": "local_album_a1b2c3",
        "name": "Nevermind (Local Edition)",
        "artists": ["Nirvana"],
        "year": 1991,
        "track_count": 12,
        "cover_url": "/api/albums/cover/local_album_a1b2c3",
        "is_local": true
      },
      {
        "id": "MPREb_jPOYfjGgApr",
        "name": "Nevermind",
        "artists": ["Nirvana"],
        "year": 1991,
        "album_art": "https://lh3.googleusercontent.com/..."
      }
    ],
    "artists": [
      {
        "id": "local_artist_d4e5f6",
        "name": "Nirvana",
        "bio": "Legendary grunge band",
        "cover_path": "/data/thumbnails/local_artist_d4e5f6.jpg",
        "is_local": true
      },
      {
        "id": "UC...",
        "name": "Nirvana",
        "avatar_art": "https://..."
      }
    ],
    "playlists": [
      {
        "id": 5,
        "name": "Nirvana Unplugged",
        "description": "A collection of unplugged tracks",
        "is_public": true,
        "owner_name": "kurt_cobain",
        "cover_url": "/api/playlists/5/cover"
      }
    ],
    "video": []
  }
}
```

**Usage notes**:
- Local tracks always appear **first** in the `tracks` array, enriched with `is_downloaded: true`
- YouTube-sourced tracks have `album_art` pointing to Google CDN (public URLs)
- Local tracks don't include an `album_art` URL — use `GET /api/tracks/cover/{video_id}` instead
- When `has_remote` is `true`, the frontend can show a "Search on YouTube Music" button
- Artist discovery is better served by `GET /api/artists/{channel_id}` (full discography)

> **Disclaimer**: The search is **local-first by default** to avoid unnecessary
> YouTube API calls and reduce latency. When you have downloaded tracks matching
> your query, only those are returned (0 API calls, instant). Use `?remote=true`
> to also fetch results from YouTube Music for discovery. The artist and album
> endpoints always fetch fresh data from YouTube.

---

## Track Streaming & Management

### GET /api/tracks/stream/{video_id}

Stream audio with seeking support (HTTP Range Requests). If the track is not yet downloaded, this endpoint auto-downloads it first.

**Headers**: `Authorization: Bearer <token>`

**Optional header**: `Range: bytes=0-1023` for seeking.

**Response**:
- **200**: Full file stream (`audio/mp4`, `audio/opus`, `audio/mpeg`)
- **206**: Partial content with seeking (`Content-Range` header included)
- **504**: Download timed out after 30 seconds

**Streaming flow**:
1. Track already downloaded → stream immediately
2. Track pending → poll DB every 0.5s up to 30s, then stream
3. Track not in DB → fetch metadata, create record, start **high-priority** streaming download, poll, stream

### GET /api/tracks/cover/{video_id}

Return the cached album cover art for a downloaded track.

**Response** (200): JPEG image.
**Response** (404): Cover not found.

### POST /api/tracks/download/{video_id}

Queue a track for background download (low-priority bucket, jitter 4-8s, macro-pause 30s every 15 downloads).

**Response** (202):
```json
{
  "status": "queued",
  "video_id": "hTWKbfoikeg",
  "title": "Smells Like Teen Spirit",
  "message": "Download queued. YouTube download takes < 1 second.",
  "stream_url": "/api/tracks/stream/hTWKbfoikeg"
}
```

If already downloaded (200):
```json
{
  "status": "success",
  "video_id": "hTWKbfoikeg",
  "title": "Smells Like Teen Spirit",
  "message": "Track is already available locally",
  "stream_url": "/api/tracks/stream/hTWKbfoikeg"
}
```

### GET /api/tracks

List all locally downloaded tracks.

**Response** (200):
```json
{
  "status": "success",
  "count": 33,
  "tracks": [
    {
      "id": "hTWKbfoikeg",
      "title": "Smells Like Teen Spirit",
      "artists": ["Nirvana"],
      "album": "Nevermind",
      "album_id": "MPREb_jPOYfjGgApr",
      "duration": 278,
      "download_status": "completed",
      "local_path": "/var/lib/zephyr/tracks/hTWKbfoikeg.m4a",
      "local_cover_path": "/static/thumbsnails/abc123.jpg",
      "created_at": "...",
      "last_listened_at": "..."
    }
  ]
}
```

### GET /api/tracks/{video_id}

Get full metadata for a track, including lyrics from disk files.

**Response** (200):
```json
{
  "video_id": "hTWKbfoikeg",
  "title": "Smells Like Teen Spirit",
  "artists": ["Nirvana"],
  "album": "Nevermind",
  "duration_seconds": 278,
  "download_status": "completed",
  "has_lyrics": true,
  "lyrics_text": "Load up on guns, bring your friends...",
  "lyrics_lrc": "[00:12.34]Load up on guns...\n[00:16.20]It's fun to lose...",
  "stream_url": "/api/tracks/stream/hTWKbfoikeg",
  "cover_url": "/api/tracks/cover/hTWKbfoikeg"
}
```

**Lyrics**: Plain text in `.txt` and synced LRC in `.lrc` files on disk (editable with `nano`).

### GET /api/tracks/{track_id}/album

Get the album browse ID for a given track. First checks the local DB, falls back to YouTube Music API.

**Response** (200):
```json
{
  "album_id": "MPREb_nnFV6SxNfSN",
  "album_name": "Fake News",
  "source": "local"
}
```

- `source: "local"` → read from DB (instant)
- `source: "remote"` → fetched from YouTube Music (fallback)

Use the `album_id` to navigate to `GET /api/albums/{album_id}`.

### GET /api/tracks/{video_id}/related

Get related songs, playlists, and artists for a track from YouTube Music's "Related" tab.

**Response** (200):
```json
{
  "video_id": "hTWKbfoikeg",
  "sections": [
    {
      "title": "You might also like",
      "contents": [
        {
          "title": "Californication",
          "videoId": "YlUKcNNmywk",
          "artists": [{"name": "Red Hot Chili Peppers"}]
        }
      ]
    },
    {
      "title": "Recommended playlists",
      "contents": [
        {
          "title": "Rock Hits",
          "playlistId": "PL..."
        }
      ]
    },
    {
      "title": "Similar artists",
      "contents": [
        {
          "title": "Radiohead",
          "browseId": "UC...",
          "subscribers": "3.2M"
        }
      ]
    },
    {
      "title": "About the artist",
      "contents": "Nirvana was an American rock band..."
    }
  ]
}
```

**Response** (404): No related content found.

---

## Albums & Artists

### GET /api/albums/{browse_id}?refresh=false

Get album details with track list and download status. Cached in local DB for subsequent calls.

**Parameters**:
- `browse_id` (required): YouTube Music album browse ID (e.g., `MPREb_jPOYfjGgApr`)
- `refresh` (optional, default `false`): bypass cache and fetch fresh data

**Response** (200):
```json
{
  "browse_id": "MPREb_nnFV6SxNfSN",
  "title": "Fake News",
  "artists": [
    {
      "name": "Pinguini Tattici Nucleari",
      "channel_id": "UCmlZgTsp0PZnbcQpvv-CyCA"
    }
  ],
  "year": 2021,
  "track_count": 16,
  "cover_url": "https://yt3.googleusercontent.com/...",
  "downloaded_count": 16,
  "cached": true,
  "tracks": [
    {
      "video_id": "jw9f60vbUH0",
      "title": "Rubami la Notte",
      "artists": ["Pinguini Tattici Nucleari"],
      "duration": "3:45",
      "video_type": "ATV",
      "is_downloaded": true,
      "download_status": "completed"
    }
  ]
}
```

**Key behavior**:
- OMV (Official Music Video) tracks are automatically resolved to ATV (Audio Track) versions.
- The resolved track list is cached in the `albums` DB table (JSONB).
- `video_type`: `ATV` (audio only) or `OMV` (music video).
- `is_downloaded`: live check against the `tracks` table.

### GET /api/albums/cover/{browse_id}

Serve the locally uploaded cover art for an album.

**Response** (200): Image file (JPEG/PNG/WebP).
**Response** (404): Cover art for this album not found.

### GET /api/artists/{channel_id}

Get artist details from YouTube Music with enriched download status.

**Parameters**:
- `channel_id` (required): YouTube Music channel ID (e.g., `UCmlZgTsp0PZnbcQpvv-CyCA`)

**Response** (200):
```json
{
  "channel_id": "UCmlZgTsp0PZnbcQpvv-CyCA",
  "name": "Pinguini Tattici Nucleari",
  "description": "Italian band from Bergamo...",
  "subscribers": "1.2M",
  "monthly_listeners": "3.5M",
  "cover_url": "https://yt3.googleusercontent.com/...",
  "top_songs": [
    {
      "video_id": "iDtqnxZiQXg",
      "title": "Hold On",
      "artists": ["Pinguini Tattici Nucleari"],
      "duration": "3:30",
      "is_downloaded": true,
      "download_status": "completed"
    }
  ],
  "albums": [
    {
      "browse_id": "MPREb_nnFV6SxNfSN",
      "title": "Fake News",
      "year": 2021,
      "cover_url": "https://..."
    }
  ],
  "singles": [
    {
      "browse_id": "MPREb_...",
      "title": "New Single",
      "year": 2024
    }
  ]
}
```

### POST /api/albums/download/{browse_id}

Download all tracks from an album in background. Also caches album metadata.

**Response** (202):
```json
{
  "album": "Fake News",
  "artists": ["Pinguini Tattici Nucleari"],
  "total_tracks": 16,
  "queued_for_download": 3,
  "already_downloaded": 13,
  "failed": 0
}
```

**Key behavior**:
- Each track is queued in the **background download bucket** (low priority, jitter 4-8s, macro-pause 30s every 15 downloads).
- Already downloaded or pending tracks are skipped.
- Failed tracks are retried.

---

## Favorites

### GET /api/favorites

List the current user's favorite tracks.

**Response** (200): Array of track objects (same shape as `GET /api/tracks`).

### GET /api/favorites/{track_id}

Check if a track is favorited.

**Response** (200):
```json
{
  "is_favorite": true
}
```

### POST /api/favorites/{track_id}

Add a track to favorites. Auto-downloads if not yet in DB.

**Response** (201):
```json
{
  "favorite_id": "hTWKbfoikeg"
}
```

### DELETE /api/favorites/{track_id}

Remove a track from favorites.

**Response** (200):
```json
{
  "favorite_id": "hTWKbfoikeg"
}
```

---

## Playlists

### GET /api/playlists

List all playlists for the current user.

**Response** (200): Array of playlist objects.

### GET /api/playlists/{id}

Get playlist details with tracks. Ownership check: private playlists are only visible to their owner. Non-existent or inaccessible playlists return 404.

**Response** (200):
```json
{
  "id": 1,
  "user_id": 1,
  "name": "My Rock Hits",
  "description": "Best rock songs",
  "cover_path": "/var/lib/zephyr/playlists_cover/1.jpg",
  "is_public": false,
  "created_at": "...",
  "updated_at": "...",
  "tracks": [
    {
      "track_id": "hTWKbfoikeg",
      "position": 1,
      "added_at": "...",
      "id": "hTWKbfoikeg",
      "title": "Smells Like Teen Spirit",
      "artists": ["Nirvana"],
      "album": "Nevermind",
      "duration": 278,
      "download_status": "completed"
    }
  ]
}
```

### POST /api/playlists

Create a new playlist.

**Request** (JSON):
```json
{
  "name": "My Rock Hits",
  "description": "Best rock songs",
  "is_public": false
}
```

**Response** (201):
```json
{
  "playlist_id": 1,
  "name": "My Rock Hits"
}
```

### PUT /api/playlists/{id}

Update playlist details (name, description, visibility).

**Request** (JSON):
```json
{
  "name": "Updated Name",
  "description": "New description",
  "is_public": true
}
```
All fields are optional — send only what you want to change.

**Response** (200):
```json
{
  "status": "updated"
}
```

### DELETE /api/playlists/{id}

Delete a playlist. Only the owner can do this.

**Response** (200):
```json
{
  "status": "deleted"
}
```

### POST /api/playlists/{id}/cover

Upload a cover image for a playlist.

**Request** (multipart/form-data):
- `file`: image file (JPEG, PNG)

**Response** (200):
```json
{
  "cover_url": "/api/playlists/1/cover"
}
```

### GET /api/playlists/{id}/cover

Get the playlist cover image.

**Response** (200): JPEG/PNG image file.
**Response** (404): No cover uploaded.

---

## Playlist Tracks

### POST /api/playlists/{id}/tracks

Add a track to a playlist. Auto-downloads if not yet in DB.

**Request** (JSON):
```json
{
  "track_id": "hTWKbfoikeg"
}
```

**Response** (201):
```json
{
  "status": "added",
  "track_id": "hTWKbfoikeg"
}
```

### DELETE /api/playlists/{id}/tracks

Remove a track from a playlist.

**Request** (JSON):
```json
{
  "track_id": "hTWKbfoikeg"
}
```

**Response** (200):
```json
{
  "status": "removed",
  "track_id": "hTWKbfoikeg"
}
```

### PUT /api/playlists/{id}/tracks/reorder

Reorder tracks in a playlist. The `new_order` array must contain all track_ids in the desired order.

**Request** (JSON):
```json
{
  "new_order": ["track_id_3", "track_id_1", "track_id_2"]
}
```

**Response** (200):
```json
{
  "status": "reordered",
  "new_order": ["track_id_3", "track_id_1", "track_id_2"]
}
```

### GET /api/playlists/{id}/tracks

Get tracks in a playlist, ordered by position.

**Response** (200): Array of track objects (same shape as in `GET /api/playlists/{id}`).

---

## Listening History

### POST /api/history

Record that the current user listened to a track.

**Request** (JSON):
```json
{
  "track_id": "hTWKbfoikeg"
}
```

**Response** (201):
```json
{
  "status": "recorded",
  "track_id": "hTWKbfoikeg"
}
```

### GET /api/history

Get the current user's listening history (most recent 75 entries).

**Response** (200):
```json
{
  "records": [
    {
      "id": 1,
      "user_id": 1,
      "track_id": "hTWKbfoikeg",
      "listened_at": "2026-07-10T12:00:00"
    }
  ]
}
```

### GET /api/history/statistics?period={period}

Aggregated listening statistics for the current user, filtered by time period.

**Query parameter**:

| `period` | Window |
|---|---|
| `1m` | Last 30 days |
| `6m` | Last 6 months |
| `1y` | Last year |
| `all` | All time (default) |

**Response** (200):
```json
{
  "period": "Last 30 days",
  "statistics": {
    "total_listens": 142,
    "unique_tracks": 38,
    "top_tracks": [
      {
        "id": "hTWKbfoikeg",
        "title": "Smells Like Teen Spirit",
        "artists": ["Nirvana"],
        "listen_count": 14
      }
    ],
    "top_artists": [
      {
        "name": "Nirvana",
        "listen_count": 31
      }
    ],
    "daily_activity": [
      { "day": "2026-06-14", "listen_count": 7 },
      { "day": "2026-06-15", "listen_count": 12 }
    ]
  }
}
```

- `top_tracks` — top 10 most played tracks in the period
- `top_artists` — top 10 most played artists (derived from `tracks.artists[]`)
- `daily_activity` — listen count per day ordered by date, ready to feed into a chart

**Response** (400): Invalid period value.

---

## Admin

All admin endpoints require `role = admin`. Auth: `Authorization: Bearer <token>`.

### GET /api/admin/users

List all users (id, username, role, is_approved, created_at).

### GET /api/admin/users/pending

List users waiting for approval.

### POST /api/admin/users/{username}/approve

Approve a pending user.

**Response** (200):
```json
{
  "status": "success",
  "message": "Admin approved the user: mario"
}
```

### POST /api/admin/curator/{username}

Promote a user to the curator role. Curators can manage tracks, albums and artists.

**Response** (200):
```json
{
  "status": "success",
  "message": "Promoted user mario to curator"
}
```

### GET /api/admin/stats

Library statistics and disk usage.

**Response** (200):
```json
{
  "status": "success",
  "stats": {
    "tracks": { "total": 250, "completed": 230, "pending": 15, "failed": 5 },
    "disk": {
      "tracks_size_mb": 1240.5,
      "thumbnails_size_mb": 45.2,
      "tracks_dir": "/data/tracks",
      "thumbnails_dir": "/data/thumbnails"
    },
    "users": { "total": 8, "pending_approval": 1 }
  }
}
```

### GET /api/admin/orphans

Find inconsistencies between DB records and files on disk.

**Response** (200):
```json
{
  "status": "success",
  "orphans": {
    "records_without_file": [
      { "id": "abc123", "title": "Lost Track", "local_path": "/data/tracks/abc123.m4a" }
    ],
    "files_without_record": [
      { "file": "orphan.m4a", "size_kb": 5120.0 }
    ]
  }
}
```

### POST /api/admin/retry-failed

Reset all `failed` tracks to `pending` and re-queue their downloads.

**Response** (200):
```json
{
  "status": "success",
  "retried_count": 5
}
```

### DELETE /api/admin/tracks/{track_id}

Permanently delete a track from the library. Removes:
- Database record (cascades to favorites, playlists, listening history)
- Audio file on disk
- Lyrics `.txt` and `.lrc` files on disk
- Cover art file (only if no other track shares the same cover)

Cannot delete tracks with `download_status = pending`.

**Response** (200):
```json
{
  "status": "success",
  "message": "Track abc123 deleted successfully"
}
```

---

## Import

### POST /api/import/csv

Import tracks from a Spotify CSV export (Exportify format).

**Request** (multipart/form-data):
- `file`: CSV file with at least these columns:
  - `Track Name` — song title
  - `Artist Name(s)` — artist name(s)
  - `Duration (ms)` — optional, but improves match accuracy

**Filename-based routing** (determined from the uploaded filename):

| Filename | Behavior |
|---|---|
| `Liked_Songs.csv` | All matched tracks added to the user's **favorites** |
| Any other name (e.g. `Forever_Young.csv`) | Creates a **private playlist** named `"Forever Young"` |

**Response** (202) — favorites mode:
```json
{
  "job_id": "b63a4e83-687d-4e3d-9daf-c4e82660c479",
  "status": "processing",
  "total": 50,
  "import_mode": "favorites",
  "status_url": "/api/import/status/b63a4e83-687d-4e3d-9daf-c4e82660c479"
}
```

**Response** (202) — playlist mode:
```json
{
  "job_id": "b63a4e83-687d-4e3d-9daf-c4e82660c479",
  "status": "processing",
  "total": 15,
  "import_mode": "playlist",
  "playlist_name": "Forever Young",
  "status_url": "/api/import/status/b63a4e83-687d-4e3d-9daf-c4e82660c479"
}
```

### GET /api/import/status/{job_id}

Poll the progress of an import job.

**Response** (200):
```json
{
  "job_id": "b63a4e83-687d-4e3d-9daf-c4e82660c479",
  "status": "completed",
  "total": 50,
  "processed": 50,
  "queued": 45,
  "failed": 5,
  "failed_tracks": [
    {
      "artist": "Unknown Artist",
      "title": "Non Existent Song",
      "reason": "No results on YouTube Music"
    },
    {
      "artist": "Radiohead",
      "title": "Creep (Very 2021 Rmx)",
      "reason": "Match score too low (4/10)"
    }
  ],
  "created_at": "2026-07-11T22:31:41"
}
```

**Import flow**:
1. Upload CSV → 202 Accepted with `job_id`
2. Poll `GET /api/import/status/{job_id}` every 2-3 seconds
3. Each row is matched against YouTube Music using:
   - Title match (exact or substring, case-insensitive)
   - Artist match (case-insensitive)
   - Duration match (±2 seconds, highest weight)
   - ATV (audio track) bonus
   - Threshold: score ≥ 6/10
4. Matched tracks are routed to favorites or a new private playlist
5. Failed tracks are listed with the reason
6. Jobs older than 3 days are automatically cleaned up

**Limits**:
- Maximum 2000 tracks per import
- Import runs in the background pool (1 thread, rate-limited)
- 50 tracks ≈ 3 minutes on the background thread

---

## Curator Operations

All curator endpoints require `role = curator` **or** `role = admin`. Auth: `Authorization: Bearer <token>`.

### POST /api/curator/tracks/upload

Upload a local audio file directly to the library — no YouTube download needed.
The track is immediately `completed` and streamable.

**Request** (`multipart/form-data`):

| Field | Type | Required | Notes |
|---|---|---|---|
| `file` | audio file | ✅ | MP3, M4A, FLAC, OGG, OPUS, WAV, AAC |
| `title` | string | ✅ | Track title |
| `artists` | string | ✅ | Comma-separated, e.g. `"Pink Floyd, Roger Waters"` |
| `album` | string | ❌ | Defaults to `"Unknown Album"` |
| `duration` | integer | ❌ | Duration in seconds |

**Response** (201):
```json
{
  "status": "created",
  "track_id": "local_a1b2c3d4e5f6",
  "title": "Wish You Were Here",
  "artists": ["Pink Floyd"],
  "album": "Wish You Were Here",
  "duration": 334,
  "stream_url": "/api/tracks/stream/local_a1b2c3d4e5f6",
  "metadata_url": "/api/tracks/local_a1b2c3d4e5f6"
}
```

> After upload you can add a cover via `POST /api/curator/tracks/{track_id}/cover` and edit metadata via `PUT /api/curator/tracks/{track_id}`.

### PUT /api/curator/tracks/{track_id}

Partially update a track's metadata. Only provided fields are changed — omitted fields remain untouched.
If `lyrics` or `lyrics_lrc` are provided, the corresponding `.txt` / `.lrc` files are written (or overwritten) on disk.

**Request** (JSON, all fields optional):
```json
{
  "title": "New Title",
  "artists": ["Artist A", "Artist B"],
  "album": "Album Name",
  "album_id": "local_album_a1b2c3",
  "lyrics": "Plain text lyrics...",
  "lyrics_lrc": "[00:12.00]First line..."
}
```

**Response** (200):
```json
{ "status": "updated", "track_id": "abc123" }
```

### POST /api/curator/tracks/{track_id}/cover

Replace the cover art for a track.

**Request** (multipart/form-data):
- `file`: image file (any format — JPEG, PNG, WebP)

**Response** (200):
```json
{ "status": "updated", "track_id": "abc123", "cover_path": "/data/thumbnails/abc123.jpg" }
```

### POST /api/curator/albums

Create a local album from tracks already in the library.
Generates a `local_album_{id}` browse_id and links all listed tracks to it.
After creation the album is immediately accessible via `GET /api/albums/{browse_id}`.

**Request** (JSON):
```json
{
  "title": "My Album",
  "artist_names": ["Artist A"],
  "year": 2024,
  "track_ids": ["video_id_1", "video_id_2", "video_id_3"]
}
```

**Response** (201):
```json
{
  "status": "created",
  "browse_id": "local_album_a1b2c3d4e5f6",
  "title": "My Album",
  "track_count": 3,
  "skipped_track_ids": [],
  "album_url": "/api/albums/local_album_a1b2c3d4e5f6"
}
```

`skipped_track_ids` lists any IDs from `track_ids` that were not found in the library (non-fatal).

### POST /api/curator/albums/{browse_id}/cover

Upload or replace a local cover photo for an album. Saved in the thumbnails directory.

**Request** (multipart/form-data):
- `file`: image file (JPEG, PNG, WebP)

**Response** (200):
```json
{
  "status": "updated",
  "browse_id": "local_album_a1b2c3d4e5f6",
  "cover_url": "/api/albums/cover/local_album_a1b2c3d4e5f6"
}
```

### POST /api/curator/artists

Create a local artist profile. The artist name must be unique (case-insensitive).
Once created, `GET /api/artists/local/{artist_id}` automatically aggregates all library tracks whose `artists` array contains this artist's name.

**Request** (JSON):
```json
{
  "name": "My Band",
  "bio": "Optional biography text"
}
```

**Response** (201):
```json
{
  "status": "created",
  "artist_id": "local_artist_a1b2c3d4e5f6",
  "name": "My Band",
  "artist_url": "/api/artists/local/local_artist_a1b2c3d4e5f6"
}
```

**Response** (409): A local artist with that name already exists.

### POST /api/curator/artists/{artist_id}/cover

Upload or replace a local artist's cover photo.

**Request** (multipart/form-data):
- `file`: image file (any format)

**Response** (200):
```json
{ "status": "updated", "artist_id": "local_artist_a1b2c3", "cover_path": "/data/thumbnails/local_artist_a1b2c3.jpg" }
```

---

## Local Artists

Local artists are created by curators and stored entirely on the VPS (no YouTube Music dependency).

### GET /api/artists/local

List all locally-created artist profiles (curator-created). Sorted alphabetically by name.
Useful for the frontend's "Local Library" browse section and curator management.

**Response** (200):
```json
{
  "status": "success",
  "count": 12,
  "artists": [
    {
      "id": "local_artist_abc123def456",
      "name": "My Band",
      "bio": "Optional bio text",
      "cover_path": "/data/thumbnails/local_artist_abc123def456.jpg",
      "is_local": true,
      "created_at": "2026-07-14T12:00:00"
    }
  ]
}
```

### GET /api/artists/local/{artist_id}

Get a local artist's profile plus all library tracks whose `artists` field contains the artist's name.
Returns the same shape as `GET /api/artists/{channel_id}` so the frontend can handle both transparently.

**Response** (200):
```json
{
  "artist_id": "local_artist_a1b2c3d4e5f6",
  "channel_id": null,
  "name": "My Band",
  "description": "Bio text...",
  "subscribers": null,
  "monthly_listeners": null,
  "cover_path": "/data/thumbnails/local_artist_a1b2c3d4e5f6.jpg",
  "top_songs": [
    {
      "video_id": "abc123",
      "title": "My Song",
      "artists": ["My Band"],
      "duration": 210,
      "is_downloaded": true,
      "download_status": "completed"
    }
  ],
  "albums": [],
  "singles": [],
  "is_local": true
}
```

**Disambiguation**: use `channel_id` (not null) to identify YouTube artists, `is_local: true` to identify local artists.

---

## Local Albums

Local albums are created by curators and stored in the same `albums` table as YouTube albums.
Their `browse_id` starts with `local_album_`. The existing `GET /api/albums/{browse_id}` serves them with no special frontend handling needed.

### GET /api/albums/local

List all locally-created albums (curator-created, `browse_id` starts with `local_album_`).
Sorted alphabetically by title. Useful for the frontend's "Local Library" browse section and curator management.

**Response** (200):
```json
{
  "status": "success",
  "count": 5,
  "albums": [
    {
      "browse_id": "local_album_abc123def456",
      "title": "My Album",
      "artists": ["My Band"],
      "year": 2024,
      "track_count": 10,
      "cover_url": "/api/albums/cover/local_album_abc123def456",
      "is_local": true,
      "cached_at": "2026-07-14T12:00:00"
    }
  ]
}
```

**Key differences from YouTube albums**:
- `cover_url` is `null` until a cover is uploaded via `POST /api/curator/tracks/{track_id}/cover`
- `video_type` for tracks is `"LOCAL"` instead of `"ATV"` or `"OMV"`
- `cached: true` is always set (they are never re-fetched from YouTube)

---

## Download System Architecture

The backend uses **two independent download buckets** with different priorities:

### Streaming Bucket (high priority)

| Property | Value |
|---|---|
| Concurrency | 1 (asyncio.Lock, FIFO queue) |
| Jitter | 1-2 seconds |
| Macro-pause | None |
| Pre-emption | Signals background to pause |
| Used by | `GET /api/tracks/stream/{video_id}` |

### Background Bucket (low priority)

| Property | Value |
|---|---|
| Concurrency | 1 (asyncio.Semaphore) |
| Jitter | 4-8 seconds |
| Macro-pause | 30 seconds every 15 consecutive downloads |
| Pre-emption | Waits when streaming is active |
| Counter reset | Resets after streaming interruption |
| Used by | `POST /api/tracks/download/{id}`, `POST /api/albums/download/{browse_id}`, `POST /api/favorites/{track_id}`, `POST /api/playlists/{id}/tracks` |

### YouTube Retry (both buckets)

| Attempt | Delay |
|---|---|
| 1 | Immediate |
| 2 | 5 seconds |
| 3 | 15 seconds |

---

## Media Types

| Extension | Content-Type | Source |
|---|---|---|
| `.m4a` | `audio/mp4` | YouTube native (AAC ~129kbps) |
| `.webm` | `audio/opus` | YouTube fallback |
| `.mp3` | `audio/mpeg` | Legacy/imported |

---

## Common Error Responses

- **400**: Bad request (missing fields, invalid data)
- **401**: Unauthorized (missing or invalid token)
- **404**: Resource not found
- **503**: YouTube Music service unavailable
- **504**: Download timed out (stream endpoint)

---

## Error Response Format

```json
{
  "detail": "Error description message"
}
```