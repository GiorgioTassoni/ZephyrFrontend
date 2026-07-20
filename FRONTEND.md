# Zephyr Frontend — Flutter Client

Build a **Spotify-like** music player app using the Zephyr backend API.
This document is designed for an AI agent (or developer) to understand the full scope,
design language, and API integration.

---

## 1. Overview

Zephyr is a self-hosted Spotify replacement backend. It downloads music from YouTube,
extracts lyrics, caches album art, and serves audio via HTTP streaming with seeking.

**Backend URL**: `http://<host>:8000`
**Auth**: JWT Bearer token (obtained via `/api/auth/login`)

---

## 2. Design Language (Spotify-like)

### Color Palette

```
Primary:   #f59e0b  (Amber Zephyr)
Bg Dark:   #121212  (main background)
Bg Card:   #1E1E1E  (cards, list items)
Bg Light:  #282828  (hover, selected)
Text:      #FFFFFF  (primary text)
Text Dim:  #B3B3B3  (secondary text, metadata)
Text Muted:#727272  (timestamps, small labels)
Error:     #E74C3C  (red)
Warning:   #F39C12  (amber)
```

### Typography

```
Headers:   Circular Std Bold / Spotify's custom font
Body:      Inter or system default
Sizes:
  AppBar:  20sp
  Title:   16sp  (track title, playlist name)
  Body:    14sp  (artist, album, descriptions)
  Small:   12sp  (duration, timestamps)
```

### Spacing

```
xs: 4px
sm: 8px
md: 16px
lg: 24px
xl: 32px
```

### Iconography

Use Material Icons or a custom icon set. Key icons:

| Icon | Usage |
|---|---|
| `play_arrow` | Play |
| `pause` | Pause |
| `skip_next` | Next track |
| `skip_previous` | Previous track |
| `shuffle` | Shuffle |
| `repeat` | Repeat |
| `favorite` / `favorite_border` | Like / Unlike |
| `search` | Search |
| `library_music` | Library |
| `home` | Home / Browse |
| `add` / `check` | Add to playlist / Added |
| `download` / `download_done` | Download / Downloaded |
| `queue_music` | Playlist |
| `history` | Listening history |
| `more_vert` | Context menu |
| `album` | Album view |
| `person` | Artist view |
| `headphones` | Now playing |

---

## 3. App Architecture

### Screens / Routes

```
/                    → Home (recently played, recommended)
/search              → Search (local-first, remote fallback)
/library             → Library (tracks, albums, artists, playlists)
/library/tracks      → All downloaded tracks
/library/albums      → Album grid (from DB + YouTube cache)
/library/artists     → Artist list
/playlist/:id        → Playlist detail
/album/:browse_id    → Album detail (with download status)
/artist/:channel_id  → Artist detail (top songs, albums, singles)
/favorites           → Favorites
/history             → Listening history
/settings            → Server URL, logout, about
```

### Bottom Navigation Bar (3-4 tabs)

```
[ Home ] [ Search ] [ Library ] [ Settings ]
```

### Now Playing Bar (persistent)

A persistent mini-player at the bottom of every screen (like Spotify):

```
[Cover art 48x48] [Track title] [Artist]  [▶/⏸] [Progress bar]
```

Tapping it opens the full-screen player.

### Full-Screen Player

```
┌──────────────────────────────┐
│                              │
│                              │
│        [Cover Art]           │
│        (large, centered)     │
│                              │
│                              │
│   [Track Title]              │
│   [Artist Name]              │
│                              │
│   ─────●─────────────        │  ← progress bar (seekable)
│   1:23          3:45         │  ← current / total
│                              │
│  [♡] [⏮] [▶⏸] [⏭] [♻]     │
│                              │
│  [Lyrics syncro]             │
│                              │
└──────────────────────────────┘
```

---

## 4. State Management (Recommended: Riverpod or BLoC)

### Core State

```dart
// Auth
class AuthState {
  String? token;
  bool isAdmin;
  bool isApproved;
}

// Player
class PlayerState {
  Track? currentTrack;
  bool isPlaying;
  Duration position;
  Duration duration;
  QueueMode queueMode; // normal, repeat, shuffle
}

// Library
class LibraryState {
  List<Track> tracks;
  List<Playlist> playlists;
  List<String> favorites; // track_ids
  List<HistoryEntry> history;
}

// Downloads
class DownloadState {
  Map<String, DownloadStatus> trackStatus; // video_id → status
}
```

### API Service Layer

```dart
class ZephyrApi {
  final String baseUrl;
  String? _token;

  // Auth
  Future<AuthResponse> login(String username, String password);
  Future<void> register(String username, String password);

  // Search
  Future<SearchResponse> search(String query, {bool remote = false});

  // Tracks
  Future<StreamResponse> streamTrack(String videoId); // Returns audio stream
  Future<TrackMetadata> getTrackMetadata(String videoId);
  Future<void> downloadTrack(String videoId);
  Future<List<Track>> getLocalTracks();
  Future<AlbumResponse> getTrackAlbum(String trackId);
  Future<RelatedResponse> getRelatedSongs(String videoId);

  // Albums & Artists
  Future<AlbumDetail> getAlbumDetail(String browseId, {bool refresh = false});
  Future<ArtistDetail> getArtistDetail(String channelId);
  Future<DownloadAlbumResponse> downloadAlbum(String browseId);

  // Favorites
  Future<List<Track>> getFavorites();
  Future<bool> isFavorite(String trackId);
  Future<void> addFavorite(String trackId);
  Future<void> removeFavorite(String trackId);

  // Playlists
  Future<List<Playlist>> getPlaylists();
  Future<Playlist> getPlaylist(int id);
  Future<int> createPlaylist(String name, String description, bool isPublic);
  Future<void> updatePlaylist(int id, {String? name, String? description, bool? isPublic});
  Future<void> deletePlaylist(int id);
  Future<void> uploadPlaylistCover(int id, File image);
  Future<void> addTrackToPlaylist(int playlistId, String trackId);
  Future<void> removeTrackFromPlaylist(int playlistId, String trackId);
  Future<void> reorderPlaylistTracks(int playlistId, List<String> newOrder);

  // History
  Future<void> recordListen(String trackId);
  Future<List<HistoryEntry>> getHistory();

  // Admin
  Future<StatsResponse> getStats();
  Future<OrphansResponse> getOrphans();
  Future<RetryResponse> retryFailed();
  Future<List<User>> getUsers();
  Future<List<User>> getPendingUsers();
  Future<void> approveUser(String username);

  // Import
  Future<ImportJob> importCsv(File file);
  Future<ImportStatus> getImportStatus(String jobId);
}
```

---

## 5. API Integration Details

### Authentication Flow

```dart
// 1. Login
final response = await api.login("username", "password");
// Store token securely (flutter_secure_storage)
await storage.write(key: "token", value: response.accessToken);

// 2. Add token to all requests
final headers = {
  "Authorization": "Bearer $token",
  "Content-Type": "application/json",
};
```

### Audio Streaming

Use `just_audio` or `audio_service` package for streaming:

```dart
final player = AudioPlayer();
// Stream URL
await player.setUrl(
  "http://host:8000/api/tracks/stream/$videoId",
  headers: {"Authorization": "Bearer $token"},
);
player.play();
```

**Seeking**: The backend supports HTTP Range Requests (206 Partial Content).
`just_audio` handles this automatically.

**Caching**: Set `Cache-Control: private, max-age=3600` (1 hour) on the backend.
The client should NOT cache audio locally — always stream from the server.

### Auto-Download on Stream

When the user taps a track that's not downloaded:
1. Call `GET /api/tracks/stream/{videoId}` → backend auto-downloads
2. Poll `GET /api/tracks/{videoId}` every 0.5s until `download_status = "completed"`
3. Then stream the audio

The backend handles this automatically. The frontend just needs to show a loading indicator.

### Cover Art

- **Downloaded tracks**: `GET /api/tracks/cover/{videoId}` → returns JPEG
- **YouTube results**: `album_art` field in search response → Google CDN URL (public)
- **Local tracks in search**: no `album_art` field → use cover endpoint

### Search Flow

1. Default: `GET /api/search?q={query}` → **local-first** (0 API calls if local matches exist)
2. Response has `has_remote: true` → show "Search on YouTube Music" button
3. User clicks button → `GET /api/search?q={query}&remote=true` → YouTube results merged
4. Each track has `is_downloaded: true/false` → show green badge or download button

### Lyrics

- `GET /api/tracks/{videoId}` → returns `lyrics_text` (plain) and `lyrics_lrc` (synced)
- Plain text: show in a scrollable view
- Synced LRC: parse timestamps and auto-scroll while playing

```dart
// Parse LRC format
class LrcLine {
  final Duration timestamp;
  final String text;
}

List<LrcLine> parseLrc(String lrc) {
  final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2})\](.*)');
  // Parse each line → LrcLine
}
```

### Related Songs

- `GET /api/tracks/{videoId}/related` → sections with "You might also like", playlists, artists
- Show as a scrollable list below the player or on the track detail page

### Import Flow

1. User gets CSV from Exportify (or similar)
2. Upload: `POST /api/import/csv` (multipart) → 202 with `job_id`
3. Poll: `GET /api/import/status/{jobId}` every 3s
4. Show progress bar: `processed / total`
5. When complete, show summary: `N queued, M failed`
6. Failed tracks: show list with reasons, user can search manually

---

## 6. UI Components (Spotify-like)

### Track List Tile

```dart
Widget trackTile(Track track, {bool showCover = true, VoidCallback? onTap}) {
  return ListTile(
    leading: showCover ? CoverImage(videoId: track.videoId, size: 48) : null,
    title: Text(track.title, style: TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(track.artists.join(", "), style: TextStyle(color: TextDim)),
    trailing: DownloadBadge(status: track.downloadStatus),
    onTap: onTap,
  );
}
```

### Album Card

```dart
Widget albumCard(Album album) {
  return Column(
    children: [
      ClipRRect(
        borderRadius: 8,
        child: Image.network(album.coverUrl, width: 160, height: 160, fit: BoxFit.cover),
      ),
      SizedBox(height: 8),
      Text(album.name, style: TextStyle(fontWeight: FontWeight.w600), maxLines: 1),
      Text(album.artists.join(", "), style: TextStyle(color: TextDim, fontSize: 12), maxLines: 1),
    ],
  );
}
```

### Playlist Card (same as Album Card but with playlist icon overlay)

### Search Result

```dart
Widget searchResult(SearchItem item) {
  return ListTile(
    leading: ClipRRect(
      borderRadius: 8,
      child: item.isDownloaded
        ? CoverImage(videoId: item.videoId, size: 48)
        : Image.network(item.albumArt, width: 48, height: 48, fit: BoxFit.cover),
    ),
    title: Text(item.title),
    subtitle: Row(
      children: [
        Text(item.artists),
        if (item.isDownloaded) ...[
          SizedBox(width: 8),
          Icon(Icons.check_circle, size: 14, color: PrimaryGreen),
        ],
      ],
    ),
    trailing: item.isDownloaded
      ? IconButton(icon: Icon(Icons.play_arrow), onPressed: () => play(item.videoId))
      : IconButton(icon: Icon(Icons.download), onPressed: () => download(item.videoId)),
  );
}
```

### Progress Bar (seekable)

```dart
Widget seekBar(Duration position, Duration duration, Function(Duration) onSeek) {
  return Column(
    children: [
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          activeTrackColor: Colors.white,
          inactiveTrackColor: BgLight,
        ),
        child: Slider(
          value: position.inMilliseconds.toDouble(),
          max: duration.inMilliseconds.toDouble(),
          onChanged: (v) => onSeek(Duration(milliseconds: v.toInt())),
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(formatDuration(position), style: TextStyle(color: TextMuted, fontSize: 12)),
          Text(formatDuration(duration), style: TextStyle(color: TextMuted, fontSize: 12)),
        ],
      ),
    ],
  );
}
```

---

## 7. Download Status Badge

Every track tile should show a status indicator:

| Status | Icon | Color | Action |
|---|---|---|---|
| `completed` | ✅ or check circle | `#1DB954` | Play |
| `pending` | ⏳ or spinner | `#F39C12` | Wait |
| `failed` | ❌ or error | `#E74C3C` | Show error, retry |
| `downloading` | 📥 or progress | `#F39C12` | Animated |
| Not in DB | 📥 or download | `#B3B3B3` | Tap to download |

---

## 8. Offline & Caching

- **Audio**: NOT cached locally. Always stream from server (10Gbps, <1s download).
- **Cover art**: Cache with `cached_network_image` package. Downloaded covers persist on server.
- **Search results**: Cache recent searches locally (SQLite or shared_preferences).
- **Playlists**: Always fetch fresh from server (they're small).
- **Library**: Fetch once on app start, refresh on pull-to-refresh.

---

## 9. Error Handling

```dart
// Wrapper for API calls
Future<T> apiCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      // Token expired → redirect to login
      authProvider.logout();
      navigator.pushReplacementNamed('/login');
    } else if (e.response?.statusCode == 404) {
      showSnackBar("Not found");
    } else if (e.response?.statusCode == 503) {
      showSnackBar("YouTube Music unavailable");
    } else {
      showSnackBar("Error: ${e.message}");
    }
    rethrow;
  }
}
```

---

## 10. Navigation Flow

```
App Launch
  │
  ├── Token stored? → Auto-login → Home
  │
  └── No token → Login Screen
        │
        ├── Register → pending approval → wait
        │
        └── Login → Home

Home
  ├── Recently played (history)
  ├── Quick links: Favorites, Playlists, Albums
  └── Continue listening (in-progress tracks)

Search
  ├── Search bar (always visible)
  ├── Local results (instant)
  ├── "Search on YouTube Music" button (if has_remote)
  └── Results: tracks, albums, artists, videos

Library
  ├── Tracks (all downloaded, sorted)
  ├── Albums (from DB, grouped)
  ├── Artists (from DB, grouped)
  └── Playlists (user-created)

Now Playing
  ├── Full-screen player
  ├── Lyrics (synced)
  ├── Related songs
  └── Queue (next tracks)
```

---

## 11. Key Packages (Flutter)

```yaml
dependencies:
  flutter_riverpod: ^2.0.0        # State management
  dio: ^5.0.0                     # HTTP client
  just_audio: ^0.9.0              # Audio streaming
  cached_network_image: ^3.0.0    # Cover art caching
  flutter_secure_storage: ^9.0.0  # Token storage
  share_plus: ^7.0.0              # Share playlists
  file_picker: ^6.0.0             # CSV import
  flutter_lyric: ^2.0.0           # LRC lyrics display (or custom)
  path_provider: ^2.0.0           # Local storage paths
  intl: ^0.18.0                   # Date formatting
```

---

## 12. Example: Complete Search Flow

```dart
// 1. User types in search bar (debounced 300ms)
// 2. Call API (local-first)
final results = await api.search(query);

// 3. Display results
if (results.hasRemote) {
  showLocalResults(results.tracks);
  showSearchOnYouTubeButton(() async {
    // 4. User clicks "Search on YouTube"
    final remoteResults = await api.search(query, remote: true);
    showMergedResults(remoteResults);
  });
} else {
  // Already includes YouTube results
  showMergedResults(results);
}

// 5. User taps a track
if (track.isDownloaded) {
  playTrack(track.videoId);
} else {
  downloadTrack(track.videoId, () {
    // After download completes, play
    playTrack(track.videoId);
  });
}
```

---

## 13. Example: Album Detail Page

```dart
// 1. Fetch album (uses cache, 0 API calls if cached)
final album = await api.getAlbumDetail(browseId);

// 2. Show album info
AppBar(title: album.title)
Subtitle: album.artists.map((a) => a.name).join(", ")
Year: album.year
Cover: album.coverUrl

// 3. Show track list
ListView(
  children: album.tracks.map((track) => TrackTile(
    title: track.title,
    subtitle: track.artists.join(", "),
    duration: track.duration,
    isDownloaded: track.isDownloaded,
    downloadStatus: track.downloadStatus,
    onTap: () => playOrDownload(track),
  )),
)

// 4. Download all button
ElevatedButton(
  onPressed: () => api.downloadAlbum(browseId),
  child: Text("Download All (${album.trackCount} tracks)"),
)

// 5. After download all → poll or refresh
```

---

## 14. Example: Player with Synced Lyrics

```dart
// 1. Get metadata (includes lyrics)
final metadata = await api.getTrackMetadata(videoId);

// 2. Parse LRC if available
List<LrcLine> lrcLines = [];
if (metadata.lyricsLrc != null) {
  lrcLines = parseLrc(metadata.lyricsLrc);
}

// 3. While playing, highlight current line
player.positionStream.listen((position) {
  final currentLine = lrcLines.lastWhere(
    (line) => line.timestamp <= position,
    orElse: () => null,
  );
  // Scroll to current line in lyrics view
  lyricsScrollController.animateTo(
    currentLineIndex * lineHeight,
    duration: 200ms,
  );
});
```

---

## 15. Zephyr Logo & Branding

The Zephyr logo (provided separately) should be used:
- App icon
- Login/Register screen header
- Settings page
- Loading splash screen

Color scheme: The Spotify-like green (`#1DB954`) can be replaced with Zephyr's brand colors if different. (#f59e0b)

---

## 16. Final Checklist

- [ ] Login/Register with JWT token storage
- [ ] Home screen with history and quick links
- [ ] Search with local-first + remote fallback
- [ ] Track streaming with `just_audio`
- [ ] Full-screen player with seek bar
- [ ] Album & Artist detail pages
- [ ] Playlist CRUD (create, add/remove tracks, reorder, cover upload)
- [ ] Favorites (heart toggle, list view)
- [ ] Listening history
- [ ] Lyrics display (plain + synced LRC)
- [ ] Related songs
- [ ] CSV import with progress polling
- [ ] Admin dashboard (stats, orphans, retry failed, user approval)
- [ ] Settings page (server URL, logout, about)
- [ ] Error handling & loading states everywhere
- [ ] Pull-to-refresh on library pages
- [ ] Dark theme (mandatory, no light theme — it's a music player!)
