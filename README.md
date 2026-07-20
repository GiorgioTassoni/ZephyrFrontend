# Zephyr — Self-Hosted Music Player (Flutter Client)

A polished, Spotify-inspired desktop/music client for the
[Zephyr](https://github.com) self-hosted music backend. It streams audio from
your own server, manages playlists, surfaces synced lyrics and listening
insights, and gives admins/curators tools to keep your local catalog tidy.

The app targets Linux desktop (Flutter Linux runner), but the codebase is
plain Flutter and runs on any platform Flutter supports.

---

## Highlights

- 🎵 **Local-first music streaming** — audio is served directly by your
  Zephyr backend over HTTP, with HTTP Range (206) seeking handled by
  `audioplayers`.
- 🔎 **Hybrid search** — instant local results, with a one-click
  "Search on YouTube Music" fallback for tracks you don't own yet.
- 📚 **Library, favorites, history** — pinned side-rail access to your
  library, favorite songs and listening history.
- 🧠 **Listening insights** — statistics screen summarising your
  listening habits.
- 📝 **Playlists** — full CRUD, drag-to-reorder, custom cover image upload,
  public/private toggle.
- 🧑‍🎨 **Curator tools** — upload tracks, fix metadata, attach covers, and
  create local artists/albums.
- 🛠️ **Admin panel** — approve users, inspect stats, find orphan files,
  retry failed downloads.
- 📥 **CSV import** — restore an Exportify-style library in one shot, with a
  live progress view.
- 🎤 **Synced lyrics + related tracks** — LRC-aware scrolling in the player,
  and an auto-similar-tracks queue when your playlist runs out.
- 🔐 **Secure session** — JWT access + refresh tokens auto-rotated by a Dio
  interceptor; tokens persisted with `shared_preferences`.
- 🌑 **Dark-only, amber-accented UI** — purposeful Spotify-like layout
  (top bar, sidebar, main pane, persistent mini player).

---

## Tech Stack

| Concern             | Choice                                 |
| ------------------- | -------------------------------------- |
| Framework           | Flutter (Dart `^3.12.2`)               |
| State management    | `flutter_riverpod` 3.x (`Notifier`)    |
| HTTP                | `dio` 5.x with an auth interceptor     |
| Audio playback      | `audioplayers` 6.x                     |
| Imagery             | `cached_network_image` 3.x             |
| Local persistence   | `shared_preferences`, `path_provider`  |
| File picking (CSV)  | `file_picker` 11.x                     |
| Date formatting     | `intl` 0.20.x                          |
| Icons               | Material Icons (built-in)              |
| Cupertino icons     | `cupertino_icons` 1.x                  |

The app explicitly bundles the transparent Zephyr logo (`References/Zephyr_trasp.png`)
as a Flutter asset, used on the splash screen, login screen and sidebar.

---

## Project Structure

```
lib/
├── main.dart                 # ProviderScope, splash & root navigation
├── api/
│   └── zephyr_api.dart       # Dio client, token rotation, all REST endpoints
├── models/
│   └── models.dart           # Track, Album, Artist, Playlist, HistoryEntry, ImportStatus
├── providers/
│   ├── auth_provider.dart    # Login/logout, auto-login, approved/admin flags
│   ├── library_provider.dart # Library, favorites, playlists, history
│   ├── navigation_provider.dart # Screen stack with back/forward
│   ├── player_provider.dart  # Audio player, queue, shuffle/repeat, history
│   └── search_provider.dart  # Local-first/remote search state
├── theme/
│   └── colors.dart           # ZephyrColors palette & dark ThemeData
├── widgets/                  # CoverImage, TrackTile, AlbumCard, PlaylistCard,
│                             # SeekBar, MiniPlayer, Toast, TrackMetadataEditor
└── screens/
    ├── main_layout.dart      # Top bar + sidebar + content + mini player
    ├── login_screen.dart
    ├── home_screen.dart
    ├── search_screen.dart
    ├── library_screen.dart
    ├── settings_screen.dart
    ├── album_detail_screen.dart
    ├── artist_detail_screen.dart
    ├── playlist_detail_screen.dart
    ├── player_screen.dart    # Full-screen player with lyrics & related
    ├── queue_screen.dart
    ├── import_screen.dart
    ├── statistics_screen.dart
    ├── admin_screen.dart
    ├── curator_screen.dart
    └── curator/              # Curator tabs (upload, edit, create artists/albums)
linux/                        # Flutter Linux runner (CMake / GTK)
```

---

## Getting Started

### Prerequisites

- Flutter SDK with Dart `^3.12.2`
- A running [Zephyr backend](https://github.com) reachable from your machine

### Install & run

```bash
flutter pub get
flutter run -d linux        # desktop (primary target)
# or
flutter run                 # any other Flutter device
```

### Build a Linux release

```bash
flutter build linux --release
```

The release bundle is produced under `build/linux/x64/release/bundle/`.

### Test

```bash
flutter test
```

---

## Configuration

On first launch you are prompted for:

1. **Server URL** — e.g. `http://localhost:8000` or `http://192.168.1.10:8000`.
   Must start with `http://` or `https://`. Saved to
   `SharedPreferences` (`zephyr_server_url`).
2. **Username / Password** — login or register. New accounts land in the
   pending queue and require admin approval before they can sign in.

Once authenticated, the access and refresh tokens are persisted
(`zephyr_auth_token`, `zephyr_refresh_token`) along with `username`,
`role`, `is_admin`, and `is_approved` flags. The app auto-resumes your
session on subsequent launches; if the access token has expired, the Dio
interceptor silently exchanges the refresh token before retrying the
original request.

You can later change the server URL or sign out from the **Settings**
screen, or via the user menu in the top bar.

---

## Architecture

### App shell

`MainLayout` paints the entire app once the user is authenticated:

```
┌──────────────────────────────────────────────────────────────┐
│  Top bar:  ◀ ▶   [search…]                  [user menu ▾]   │
├────────────┬─────────────────────────────────────────────────┤
│            │                                                 │
│  Sidebar   │                Current screen                   │
│  · Home    │                (Home / Search / Library /        │
│  · Library │                 Album / Artist / Playlist /     │
│  · Favorite│                 Player / Queue / Settings …)    │
│  · Insights│                                                 │
│  + Lists   │                                                 │
│  of plays. │                                                 │
│            │                                                 │
├────────────┴─────────────────────────────────────────────────┤
│  Mini-player: cover · title · ♥   ⇄ ⏮ ⏯ ⏭ 🔁   ⟲ queue ▶   │
└──────────────────────────────────────────────────────────────┘
```

The sidebar always reflects your playlist list and any active selection
is highlighted in the amber primary color. The top bar exposes circular
back/forward history buttons and a centered search field.

### Routing & navigation

`NavigationProvider` keeps a `currentScreen` plus `backStack` /
`forwardStack`, so the top-bar arrows behave like a real browser. The
`ScreenType` enum has 15 variants:
`home`, `search`, `library`, `settings`, `album`, `artist`, `playlist`,
`favorites`, `history`, `admin`, `import`, `lyrics`, `queue`, `curator`,
`statistics`. When the auth token disappears (logout, forced
invalidation), navigation is reset to `home`.

### Player

`PlayerNotifier` wraps an `audioplayers` `AudioPlayer` and exposes a
`ZephyrPlayerState` containing:

- `currentTrack`, `position`, `duration`, `isPlaying`
- `queue`, `originalQueue` (pre-shuffle), `userQueue` (priority queue
  for "Add to queue")
- `queueMode` (`normal`, `repeat_all`, `repeat_one`) and `isShuffled`
- `volume` (persisted)

The stream URL is `${baseUrl}/api/tracks/stream/{videoId}?token={jwt}`
so the audio decoder carries its own authorization. When the queue runs
out, the notifier queries `/api/tracks/{id}/related` and auto-streams
similar tracks. A listen counts toward history once playback crosses the
halfway mark (or 15s, whichever comes first).

### API layer

`ZephyrApi` is a singleton wrapping `dio.Dio`:

- Attaches `Authorization: Bearer <access>` to every request via an
  interceptor.
- On a `401`, performs a single transparent refresh against
  `/api/auth/refresh` using the refresh token as the Bearer, then
  replays the original request. If the refresh fails, an
  `onUnauthorized` callback hands control back to the auth provider.
- Exposes strongly-typed helpers for every backend endpoint used by the
  UI: auth, search, tracks, albums, artists, favorites, playlists,
  history, statistics, admin (users, stats, orphans, retry), CSV
  import, curator uploads, etc.

### Theming

`lib/theme/colors.dart` defines the full Spotify-inspired palette with a
Zephyr twist:

```
primary   #f59e0b   Amber Zephyr
bgDark    #121212   Main background
bgCard    #1E1E1E   Cards, tiles
bgLight   #282828   Hover, selected
text      #FFFFFF   Primary text
textDim   #B3B3B3   Secondary text
textMuted #727272   Timestamps, captions
error     #E74C3C
warning   #F39C12
success   #1DB954
```

`Material 3` is on, brightness is dark (only), and the `NavigationBar`,
`AppBar`, `Slider`, etc. inherit a coherent `darkTheme`. A
`ResponsiveSizing` extension gently scales text on wider windows so the
UI breathes on big monitors.

---

## Feature tour

### Search

- Local-first queries are sent against `/api/search?q=…`. If the
  response has `has_remote: true`, a "Search on YouTube Music" button
  appears that fires `?remote=true`.
- Each result row shows its download state via a status badge
  (`completed`, `pending`, `downloading`, `failed`, or a download
  button when the track is not in your library).

### Library

Tabbed view over your downloaded tracks, albums, artists, and playlists.
Pull-to-refresh re-fetches from the backend.

### Album & Artist detail

Albums display the artwork, year, track list and a "Download all"
action. Artists surface top songs, albums, and singles.

### Playlists

Create, rename, delete, toggle public, reorder tracks, upload a cover
image, and drill into any playlist from the sidebar.

### Mini player & full-screen player

The bottom bar is always-on and mirrors the full-screen player: shuffle,
previous, play/pause, next, repeat (`normal → repeat_all → repeat_one`),
plus seek, queue, lyrics/related, and volume. Tapping the cover art
opens the full-screen `PlayerScreen` which shows lyrics (parsed from LRC
when available), the current track's related songs, and the queue.

### Listening insights

The `statistics_screen` fetches aggregates from `/api/history/statistics`
so you can see your top artists/tracks/listening volume.

### Admin panel

If your `role` is `admin`, the top-bar menu exposes an `Admin Panel`:

- Stats overview (`/api/admin/stats`)
- Orphan files (`/api/admin/orphans`)
- Retry-failed downloads (`/api/admin/retry-failed`)
- Approve pending users (`/api/admin/users/pending` → approve)
- Promote users to curator
- Delete individual tracks

### Curator panel

If your role is `curator` (or `admin`), the `CuratorScreen` lets you:

- Upload audio files with title/artist (multipart upload)
- Edit track metadata: title, artists, album assignment, lyrics (plain
  text + LRC)
- Upload custom track / album / artist cover images
- Create local artists and albums and assemble them from your tracks

### CSV import

Drop an Exportify-style CSV and the app posts it to `/api/import/csv`,
then polls `/api/import/status/{jobId}` to show live
`processed / total` progress and a list of failures.

---

## Networking notes

- All requests carry `Authorization: Bearer <jwt>` from the
  interceptor — only `login`, `refresh`, `logout`, and `register` are
  exempt.
- Stream URLs embed the access token in the query string because
  `audioplayers` may issue media-element requests that bypass Dio's
  headers.
- Cover art is fetched from `/api/tracks/cover/{videoId}` and cached via
  `cached_network_image`. Audio is **not** cached client-side — always
  streamed from your server.

---

## Error handling

- Network failures from the Dio client are surfaced through
  `ZephyrApi._handleDioError`, returning human-readable messages
  ("Failed to connect to Zephyr server. Make sure base URL is correct.",
  unreachable server timeouts, etc.).
- Expired refresh tokens trigger `AuthNotifier.forceLogout(...)`, which
  wipes the local credentials and bounces the user back to the login
  screen with a toast-style "session expired"-style message.

---

## License

No LICENSE file is currently committed to this repository. Treat the
code as "all rights reserved" until the project owners add one.
