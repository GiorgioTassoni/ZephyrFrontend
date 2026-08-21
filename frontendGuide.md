# Zephyr Frontend Architecture & Developer Guide

This document is the comprehensive guide to the architecture, classes, state management, and operational contracts of the **Zephyr Flutter Frontend**. It is designed to give AI agents and human engineers full clarity on how the client application is structured and how its subsystems interact.

### Repository Layout (monorepo)

```
packages/zephyr_core/   # Shared code: api/, models/, providers/, screens/, widgets/, utils/, theme/
apps/zephyr_mobile/     # Android app shell (audio_service bootstrap)
apps/zephyr_desktop/    # Linux + Windows app shell (MPRIS via MediaControls seam)
```

Each shell is its own Flutter project depending on `zephyr_core` by path. Platform-specific integrations are registered at startup through seams in core (e.g. `MediaControlsService`); shared code contains no `Platform.is*` branching for OS-specific services. Build each app from inside its folder (`flutter build linux` in `apps/zephyr_desktop`, `flutter build apk` in `apps/zephyr_mobile`).

---

## 1. High-Level Architecture

Zephyr is a cross-platform music streaming and personal library application built with **Flutter** (supporting Linux desktop and Android).

```
┌────────────────────────────────────────────────────────────────────────┐
│                               UI Layer                                 │
│  MainLayout • PlayerScreen • HomeScreen • Library • Admin • Modals    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Watches / Reads
┌───────────────────────────────────▼────────────────────────────────────┐
│                        State Management (Riverpod)                     │
│   playerProvider   •   libraryProvider   •   authProvider   •  nav    │
└───────────────────┬───────────────────────────────┬────────────────────┘
                    │ Commands / Streams            │ HTTP & SSE
┌───────────────────▼─────────────┐   ┌─────────────▼────────────────────┐
│      Audio Playback Engine      │   │          API & Network           │
│  ZephyrAudioHandler (just_audio)│   │  ZephyrApi (Dio + Auth Intercept)│
│  MprisMediaControls (D-Bus MPRIS,│   │  Local Proxy (Header Injection)  │
│    desktop shell only)          │   │  SSE Stream (State, Tracks, Lib) │
└─────────────────────────────────┘   └──────────────────────────────────┘
```

### Core Technologies
- **State Management**: [Flutter Riverpod](https://riverpod.dev/) (`StateNotifier`, `NotifierProvider`, `ref.watch`).
- **Networking**: [Dio](https://pub.dev/packages/dio) with custom interceptors for Bearer tokens + `dart:io` `HttpClient` for Server-Sent Events (SSE).
- **Audio Output**: 
  - `just_audio` via `ZephyrAudioHandler` (`audio_service`) for mobile background audio, lockscreen metadata, and notification controls.
  - `audioplayers` fallback.
  - `MprisMediaControls` (desktop shell) for Linux desktop media keys (D-Bus MPRIS protocol), registered via the `MediaControlsService` seam in zephyr_core.
- **Security Standard (S-03)**: Auth tokens are **never passed as URL query parameters**. A local loopback HTTP proxy (`http://localhost:<port>/stream/<id>`) injects the `Authorization: Bearer <token>` header dynamically into audio stream requests.

---

## 2. Fundamental Architectural Contracts

### 2.1. Playback Order: Stream First, Metadata Second
1. **Never call `GET /api/tracks/{id}` before starting playback.** A track row does not exist in the backend database until it has been resolved/streamed at least once (calling metadata first returns `404 Not Found`).
2. **Start playback with `GET /api/tracks/stream/{id}`**: This endpoint auto-resolves YouTube/Deezer audio, begins streaming immediately, queues download in the background, and persists the DB row.
3. **Wait for `event: track_status` SSE**: When download finishes (`download_status: 'completed'`), the backend broadcasts `track_status`. The frontend receives this event and calls `_api.getTrackMetadata(trackId)` to enrich the track with lyrics, album metadata, and cover art.

### 2.2. Canonical Track IDs & Prefix Agnosticism
- Deezer-origin tracks are formatted canonically as `dz_<id>` (e.g. `dz_3135551`).
- Backend endpoints and SSE events sometimes emit the raw numeric string (`3135551`) or the prefixed string (`dz_3135551`).
- **Rule**: Always compare track IDs using the `_isSameTrack(a, b)` helper function in [`lib/providers/player_provider.dart`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/providers/player_provider.dart), which strips the `dz_` prefix before equality comparison.

### 2.3. Multi-Device Playback & Ownership
- **Owner Device (`isPlayerDevice: true`)**: The physical device running audio playback through its speakers. Listens to remote SSE commands (`play_track`, `pause`, `seek`, `next`, `previous`).
- **Remote Control Device (`isPlayerDevice: false`)**: Acts as a remote control. Dispatches state updates and commands to `/api/player/state` and `/api/player/command`.
- **Standalone Auto-Claim**: If only one device is detected on the network (`connectedDevices` has no other devices), it automatically claims the **Owner** role.
- **Takeover (`takeoverPlayback`)**: A remote device can take over playback by saving its current position, calling `POST /api/player/takeover`, claiming ownership, and calling `playTrack(..., initialPosition: currentPos)`.
- **Startup Protection**: On app launch, playback is strictly **PAUSED**. The frontend must never auto-play audio on startup even if the backend Redis snapshot has `is_playing: true`.

---

## 3. Directory & File Structure

```
lib/
├── main.dart                   # Application entrypoint, Riverpod ProviderScope, theme init
├── api/
│   └── zephyr_api.dart         # REST & SSE communication layer, loopback proxy server
├── models/
│   └── models.dart             # All data models (Track, Album, Artist, Playlist, User, etc.)
├── providers/
│   ├── auth_provider.dart      # Authentication, JWT token storage, user roles
│   ├── library_provider.dart   # Favorites, playlists, downloads, history
│   ├── navigation_provider.dart# Custom screen navigation stack
│   ├── player_provider.dart    # Player state machine, queue, multi-device sync
│   └── search_provider.dart    # Search query state
├── screens/
│   ├── main_layout.dart        # Responsive root frame (Sidebar, TopBar, MiniPlayer, Body)
│   ├── player_screen.dart      # Fullscreen player (Synchronized lyrics, visualizer, related)
│   ├── home_screen.dart        # Featured albums, recently played, favorites shortcuts
│   ├── library_screen.dart     # Tabbed library (Playlists, Albums, Artists, Downloads)
│   ├── favorites_screen.dart   # User's favorited tracks
│   ├── playlist_detail_screen.dart # Playlist tracks, reordering, metadata editing
│   ├── album_detail_screen.dart    # Album tracks and artwork
│   ├── artist_detail_screen.dart   # Artist top tracks, albums, related artists
│   ├── search_screen.dart      # Multi-source search (Deezer, YouTube, Local)
│   ├── queue_screen.dart       # Play queue management & reordering
│   ├── statistics_screen.dart  # Listening Insights & stats
│   ├── settings_screen.dart    # App settings, audio quality, server connection
│   ├── admin_screen.dart       # Admin panel (YouTube cookies, users, system health)
│   ├── curator/                # Track/album curation & local file upload tabs
│   ├── import_screen.dart      # Spotify/Deezer playlist import
│   ├── login_screen.dart       # Login & server URL setup
│   └── change_password_screen.dart # Password management
├── theme/
│   ├── colors.dart             # Zephyr visual color tokens (Dark theme palette)
│   └── zephyr_theme.dart       # Flutter ThemeData, typography, button styles
├── utils/
│   ├── audio_handler.dart      # Background audio_service & MediaSession handler
│   ├── media_controls.dart     # MediaControlsService seam (shells register MPRIS etc.)
│   ├── device_info.dart        # Device ID & device name discovery
│   └── root_navigator.dart     # Global root navigator key for dialogs
└── widgets/
    ├── track_tile.dart         # Standard track row with context menu, hover, play state
    ├── mini_player.dart        # Bottom persistent player bar
    ├── devices_modal.dart      # Device switcher & takeover modal
    ├── seek_bar.dart           # Custom audio scrubbing bar
    ├── cover_image.dart        # Cached network image with fallback placeholders
    ├── favorite_button.dart    # Heart button connected to libraryProvider
    ├── player_song_context_menu.dart # Context menu for tracks (Add to queue, playlist, etc.)
    ├── unresolved_track_modal.dart   # Track resolution / candidate selection modal
    └── track_metadata_editor_dialog.dart # ID3 tag & metadata editor dialog
```

---

## 4. State Management (Providers)

### 4.1. `PlayerProvider` (`lib/providers/player_provider.dart`)
Controls the audio playback lifecycle and multi-device synchronization.

- **State Model**: `ZephyrPlayerState`
  - `currentTrack`: Active [`Track`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/models/models.dart#L1) object (or null).
  - `queue`: Active list of upcoming tracks.
  - `isPlaying`: Boolean playback status.
  - `isLoading`: Boolean buffering/resolving status (drives play/pause button loading spinner).
  - `position` & `duration`: Audio timeline durations.
  - `effectiveDuration`: Computes `duration > 0 ? duration : currentTrack.duration`.
  - `isPlayerDevice`: Whether this device outputs sound or acts as a remote.
  - `activeDeviceId` & `activeDeviceName`: Name/ID of the device outputting sound.
  - `connectedDevices`: List of all devices connected to the account.
- **Key Methods**:
  - `playTrack(Track track, List<Track> queue, {Duration? initialPosition})`: Starts playback. If remote, sends `PUT /api/player/state` + `POST /api/player/command`. If owner, streams via proxy.
  - `togglePlayPause()`, `resume()`, `pause()`, `seek(Duration position)`: Transport controls.
  - `playNext()`, `playPrevious()`: Queue navigation with automatic history tracking.
  - `takeoverPlayback({bool force = false})`: Switches playback ownership to this device without losing playback position.
  - `_applyServerStateSnapshot(Map<String, dynamic> snapshot)`: Ingestion point for SSE `event: state`, `event: devices`, `event: track_status`, and `event: library`.

### 4.2. `LibraryProvider` (`lib/providers/library_provider.dart`)
Manages the user's personal collection and favorites.

- **State Model**: `LibraryState`
  - `favoriteTracks`: List of tracks marked as favorite.
  - `userPlaylists`: Playlists created by the user.
  - `downloadedTracks`: Tracks saved locally in the backend DB.
  - `historyTracks`: Recently played tracks.
- **Key Methods**:
  - `toggleFavorite(Track track)`: Optimistically toggles favorite status and syncs via API.
  - `handleTrackStatusEvent({required String trackId, required String downloadStatus})`: Updates track download badges when downloads complete.
  - `handleLibraryEvent(...)`: Handles real-time cross-device library changes (playlist additions, deletes).

### 4.3. `AuthProvider` (`lib/providers/auth_provider.dart`)
Handles authentication, user roles, and token lifecycle.

- **State Model**: `AuthState` (`user`, `token`, `isAdmin`, `isAuthenticated`).
- **Storage**: Persists JWT token and server URL to `SharedPreferences`.

### 4.4. `NavigationProvider` (`lib/providers/navigation_provider.dart`)
Manages screen transitions and navigation history within the desktop/tablet/mobile layout without destroying global player state.

---

## 5. API Layer (`lib/api/zephyr_api.dart`)

The `ZephyrApi` class is a singleton that wraps all REST endpoints and SSE streams.

### 5.1. Authentication & Security
- Requests pass through a Dio interceptor that injects `Authorization: Bearer <token>`.
- Cover images are retrieved via `getCoverUrl(videoId)` with token headers.

### 5.2. Loopback Streaming Proxy
- `getStreamProxyUrl(videoId)`: Returns `http://localhost:<proxyPort>/stream/<videoId>`.
- The local proxy intercepts incoming audio engine requests and proxies them to `$baseUrl/api/tracks/stream/$videoId`, dynamically injecting the Bearer token. This guarantees compatibility with audio engines that don't allow custom HTTP headers.

### 5.3. Server-Sent Events (SSE)
- `subscribeToPlayerEvents(deviceId, {deviceName})`: Connects to `GET /api/player/events` (SSE).
- Parses wire events:
  - `event: state`: Real-time player snapshot (`current_track_id`, `is_playing`, `position_ms`, `queue`).
  - `event: devices`: List of active devices.
  - `event: track_status`: Notifies that a background download finished (`download_status: completed | failed`).
  - `event: library`: Real-time playlist and favorite mutations.

### 5.4. Offline Downloads & Local Device Storage
- `OfflineStorageService` (`lib/utils/offline_storage.dart`): Persistent on-device audio manager saving `.m4a` audio files, `.jpg` cover art, and `.lrc` synchronized lyrics into sandboxed app storage via `path_provider`.
- `offlineDownloadsProvider` (`lib/providers/offline_provider.dart`): Riverpod provider managing on-device download state, live progress fractions, and batch downloading.
- `downloadTrackAudioFile(trackId, savePath)`: Streams raw audio files directly via `GET /api/tracks/download/{track_id}` to local device storage.
- `PlayerProvider`: Directly detects locally downloaded tracks and routes playback through local files (`DeviceFileSource` / `playFilePath`), ensuring seamless playback even when disconnected from the VPS.

### 5.5. Offline Listening History Sync
- `syncHistory(listens)`: Flushes buffered offline listens via `POST /api/history/sync` with `{ "listens": [ { "track_id": ..., "played_at": ..., "client_id": ... } ] }`. Client IDs ensure idempotent deduplication.

### 5.6. Admin API
- `getYoutubeCookies()`: Fetches current status of the backend YouTube cookies file.
- `uploadYoutubeCookies(File file)`: Uploads a fresh `cookies.txt` via multipart form upload.

---

## 6. Models (`lib/models/models.dart`)

| Model Class | Description |
|---|---|
| [`Track`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/models/models.dart#L1) | Represents a song. Holds `videoId` (`dz_...`), `title`, `artists`, `album`, `duration`, `downloadStatus`, `coverUrl`, `lyricsText`, `lyricsLrc`, `localPath`. |
| [`Album`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/models/models.dart#L337) | Represents a music album with tracks and release year. |
| [`Artist`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/models/models.dart#L491) | Represents an artist with top tracks, albums, singles & EPs, and cover image (unified schema across YouTube & Deezer `dz_` paths). |
| [`Playlist`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/models/models.dart#L508) | User-created or curated playlist with ordered tracks. |
| [`PlaylistDownloadManifest`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/models/models.dart#L990) | Batch playlist download manifest with track list and status counts (`ready`, `queued`, `needs_resolution`). |
| [`User`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/models/models.dart#L590) | User account with permissions (`role: admin | user`). |
| [`ListeningInsight`](file:///home/GioViale/Projects/Python/Zephyr/frontend/lib/models/models.dart#L644) | Analytics and statistics model for user listening habits. |

---

## 7. Key Screens & Workflows

### 7.1. Main Layout (`lib/screens/main_layout.dart`)
- Hosts the responsive framework:
  - **Desktop / Wide**: Persistent left navigation sidebar, top search bar, central content canvas, persistent bottom player bar.
  - **Mobile**: Bottom navigation bar + floating mini-player.
- Contains the **Device Switcher chip**: Displays active player device; tapping prompts instant playback takeover.

### 7.2. Player Screen (`lib/screens/player_screen.dart`)
- **Synchronized Lyrics**: Parses `.lrc` timestamps and highlights active lines in real-time matching `playerState.position`.
- **Lyrics Subscription**: Subscribes to `_api.onLyricsReady` stream so lyrics appear immediately when download completes.
- **Audio Visualizer**: Animated waveform responsive to playback state.
- **Related Songs & Radio**: Suggestions based on current artist/album.

### 7.3. Admin Panel (`lib/screens/admin_screen.dart`)
- Restricted to users with `role: admin`.
- Displays system health, download worker metrics, user management, and **YouTube Cookie Health Card** (with upload button for `cookies.txt`).

---

## 8. Guidelines for AI Agents Modifying Frontend Code

1. **Never break S-03 Token Compliance**: Never put tokens in stream URLs (`?token=...`). Always use `_api.getStreamProxyUrl(videoId)`.
2. **Never change playback order**: Always stream first (`/api/tracks/stream/{id}`), listen for `track_status` SSE, and enrich metadata only after download completes.
3. **Always use `_isSameTrack(a, b)`**: Do not use `==` directly when comparing track IDs, as ID formats may vary between `dz_123` and `123`.
4. **Never run git commands**: Do not commit or push unless explicitly instructed by the user.
5. **Keep English Copy**: All user-facing strings, logs, and labels must remain in English.
6. **Always run `flutter analyze`**: After completing modifications, run `flutter analyze` to verify that no compiler errors or broken types were introduced.

### 8.1. Versioning & Release Channels

The numeric application version is defined once in `pubspec.yaml` using Flutter's standard format:

```yaml
version: 1.1.0+10
```

The Settings screen reads the installed version through `package_info_plus`, so it must not hardcode a version number. The release channel is supplied at build time through the `RELEASE_CHANNEL` Dart define:

```bash
flutter build apk --release --dart-define=RELEASE_CHANNEL=Preview
flutter build windows --release --dart-define=RELEASE_CHANNEL=Stable
```

If `RELEASE_CHANNEL` is omitted, the app defaults to `Preview`. Supported channel names are not restricted by the client, so CI can use values such as `Preview`, `Beta`, or `Stable`.
