class Track {
  final String videoId; // Canonical track ID (e.g. dz_3135551, local_123)
  final String? ytId; // Optional backend YouTube source ID
  final String title;
  final List<String> artists;
  final List<String> artistsIds;
  final String? album;
  final String? albumId;
  final Duration? duration;
  final String downloadStatus; // 'completed', 'pending', 'failed', 'downloading', 'discovered', 'not_in_db'
  final String? localPath;
  final String? localCoverPath;
  final String? coverUrl;
  final bool isDownloaded;
  final String? lyricsText;
  final String? lyricsLrc;

  Track({
    required this.videoId,
    this.ytId,
    required this.title,
    required this.artists,
    this.artistsIds = const [],
    this.album,
    this.albumId,
    this.duration,
    required this.downloadStatus,
    this.localPath,
    this.localCoverPath,
    this.coverUrl,
    required this.isDownloaded,
    this.lyricsText,
    this.lyricsLrc,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    // Determine canonical track ID (track_id ?? id ?? video_id ?? videoId)
    String rawVId = (json['track_id'] ?? json['id'] ?? json['video_id'] ?? json['videoId'])?.toString().trim() ?? '';
    if (rawVId == 'null') rawVId = '';

    String vId = rawVId;
    if (vId.isNotEmpty && RegExp(r'^\d+$').hasMatch(vId)) {
      vId = 'dz_$vId';
    }

    String? yId = json['yt_id']?.toString().trim();
    if (yId == 'null' || yId == '') yId = null;

    // Determine artists list & IDs
    List<String> artistsList = [];
    List<String> artistsIdsList = [];

    dynamic rawArtists = json['artists'] ??
        json['artist'] ??
        json['artist_name'] ??
        json['artist_names'] ??
        json['artistName'] ??
        json['author'] ??
        json['authors'] ??
        json['channel'] ??
        json['channel_name'] ??
        json['uploader'] ??
        json['creator'];

    if (rawArtists != null) {
      if (rawArtists is String) {
        artistsList = rawArtists
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (rawArtists is List) {
        for (final e in rawArtists) {
          if (e is Map) {
            final name = (e['name'] ?? e['title'] ?? e['artist'] ?? '').toString().trim();
            final id = (e['id'] ?? e['channel_id'] ?? e['artist_id'] ?? e['browse_id'] ?? e['channelId'] ?? '').toString().trim();
            if (name.isNotEmpty) artistsList.add(name);
            if (id.isNotEmpty) {
              final formattedId = RegExp(r'^\d+$').hasMatch(id) ? 'dz_$id' : id;
              artistsIdsList.add(formattedId);
            }
          } else if (e != null) {
            final s = e.toString().trim();
            if (s.isNotEmpty) artistsList.add(s);
          }
        }
      } else if (rawArtists is Map) {
        final name = (rawArtists['name'] ?? rawArtists['title'] ?? rawArtists['artist'] ?? '').toString().trim();
        final id = (rawArtists['id'] ?? rawArtists['channel_id'] ?? rawArtists['artist_id'] ?? rawArtists['browse_id'] ?? rawArtists['channelId'] ?? '').toString().trim();
        if (name.isNotEmpty) artistsList.add(name);
        if (id.isNotEmpty) {
          final formattedId = RegExp(r'^\d+$').hasMatch(id) ? 'dz_$id' : id;
          artistsIdsList.add(formattedId);
        }
      }
    }

    // Fallback if artistsList is still empty
    if (artistsList.isEmpty) {
      final fallbackName = (json['artist_name'] ??
              json['artist'] ??
              json['artistName'] ??
              json['author'] ??
              json['authors'] ??
              json['channel_name'] ??
              json['uploader'] ??
              json['creator'] ??
              '')
          .toString()
          .trim();
      if (fallbackName.isNotEmpty) {
        artistsList.add(fallbackName);
      }
    }

    // Filter out category labels incorrectly returned as artist names
    const invalidCategoryLabels = {'song', 'canzone', 'single', 'ep', 'video', 'track'};
    artistsList = artistsList.where((a) => !invalidCategoryLabels.contains(a.trim().toLowerCase())).toList();

    if (artistsIdsList.isEmpty) {
      if (json['artists_ids'] != null && json['artists_ids'] is List) {
        artistsIdsList = (json['artists_ids'] as List).map<String>((e) {
          final s = e.toString().trim();
          return RegExp(r'^\d+$').hasMatch(s) ? 'dz_$s' : s;
        }).where((e) => e.isNotEmpty).toList();
      } else if (json['artist_ids'] != null && json['artist_ids'] is List) {
        artistsIdsList = (json['artist_ids'] as List).map<String>((e) {
          final s = e.toString().trim();
          return RegExp(r'^\d+$').hasMatch(s) ? 'dz_$s' : s;
        }).where((e) => e.isNotEmpty).toList();
      } else if (json['artist_id'] != null && json['artist_id'].toString().trim().isNotEmpty) {
        final aid = json['artist_id'].toString().trim();
        artistsIdsList = [RegExp(r'^\d+$').hasMatch(aid) ? 'dz_$aid' : aid];
      } else if (json['channel_id'] != null && json['channel_id'].toString().trim().isNotEmpty) {
        final cid = json['channel_id'].toString().trim();
        artistsIdsList = [RegExp(r'^\d+$').hasMatch(cid) ? 'dz_$cid' : cid];
      }
    }

    // Determine album ID formatting
    String? albId = (json['album_id'] ?? json['albumId'])?.toString();
    if (albId != null && albId.isNotEmpty && RegExp(r'^\d+$').hasMatch(albId)) {
      albId = 'dz_$albId';
    }

    // Determine duration
    Duration? trackDuration;
    if (json['duration'] != null) {
      if (json['duration'] is int) {
        trackDuration = Duration(seconds: json['duration']);
      } else if (json['duration'] is double) {
        trackDuration = Duration(seconds: (json['duration'] as double).toInt());
      } else if (json['duration'] is String) {
        final str = (json['duration'] as String).trim();
        if (RegExp(r'^\d+$').hasMatch(str)) {
          trackDuration = Duration(seconds: int.parse(str));
        } else {
          final parts = str.split(':');
          if (parts.length == 2) {
            final m = int.tryParse(parts[0]) ?? 0;
            final s = int.tryParse(parts[1]) ?? 0;
            trackDuration = Duration(minutes: m, seconds: s);
          } else if (parts.length == 3) {
            final h = int.tryParse(parts[0]) ?? 0;
            final m = int.tryParse(parts[1]) ?? 0;
            final s = int.tryParse(parts[2]) ?? 0;
            trackDuration = Duration(hours: h, minutes: m, seconds: s);
          }
        }
      }
    } else if (json['duration_seconds'] != null) {
      final ds = json['duration_seconds'];
      if (ds is int) {
        trackDuration = Duration(seconds: ds);
      } else if (ds is double) {
        trackDuration = Duration(seconds: ds.toInt());
      } else {
        trackDuration = Duration(seconds: int.tryParse(ds.toString()) ?? 0);
      }
    }

    // Determine cover URL
    String? cUrl = (json['cover_url'] ??
            json['cover_art'] ??
            json['cover'] ??
            json['album_art'] ??
            json['albumArt'] ??
            json['album_cover'])
        ?.toString();

    if ((cUrl == null || cUrl.isEmpty) && json['album'] is Map) {
      final alb = json['album'] as Map;
      cUrl = (alb['cover_url'] ??
              alb['cover_art'] ??
              alb['cover_big'] ??
              alb['cover_medium'] ??
              alb['cover_xl'] ??
              alb['cover'])
          ?.toString();
    }

    // Determine download status
    String status = (json['download_status'] ?? 'not_in_db').toString();
    bool downloaded = json['is_downloaded'] ?? (status == 'completed');

    return Track(
      videoId: vId,
      ytId: yId,
      title: (json['title'] ?? json['name'] ?? 'Unknown Track').toString(),
      artists: artistsList,
      artistsIds: artistsIdsList,
      album: json['album'] is String
          ? json['album']
          : (json['album'] is Map
              ? json['album']['name']?.toString() ?? json['album']['title']?.toString()
              : json['album_title']?.toString()),
      albumId: albId,
      duration: trackDuration,
      downloadStatus: status,
      localPath: json['local_path']?.toString(),
      localCoverPath: json['local_cover_path']?.toString(),
      coverUrl: cUrl,
      isDownloaded: downloaded,
      lyricsText: json['lyrics_text']?.toString(),
      lyricsLrc: json['lyrics_lrc']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'track_id': videoId,
      'video_id': videoId,
      'yt_id': ytId,
      'title': title,
      'artists': artists,
      'artists_ids': artistsIds,
      'album': album,
      'album_id': albumId,
      'duration': duration?.inSeconds,
      'download_status': downloadStatus,
      'local_path': localPath,
      'local_cover_path': localCoverPath,
      'cover_url': coverUrl,
      'is_downloaded': isDownloaded,
      'lyrics_text': lyricsText,
      'lyrics_lrc': lyricsLrc,
    };
  }

  Track copyWith({
    String? videoId,
    String? ytId,
    String? title,
    List<String>? artists,
    List<String>? artistsIds,
    String? album,
    String? albumId,
    Duration? duration,
    String? downloadStatus,
    String? localPath,
    String? localCoverPath,
    String? coverUrl,
    bool? isDownloaded,
    String? lyricsText,
    String? lyricsLrc,
  }) {
    return Track(
      videoId: videoId ?? this.videoId,
      ytId: ytId ?? this.ytId,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      artistsIds: artistsIds ?? this.artistsIds,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      duration: duration ?? this.duration,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      localPath: localPath ?? this.localPath,
      localCoverPath: localCoverPath ?? this.localCoverPath,
      coverUrl: coverUrl ?? this.coverUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      lyricsText: lyricsText ?? this.lyricsText,
      lyricsLrc: lyricsLrc ?? this.lyricsLrc,
    );
  }
}

class Album {
  final String id;
  final String name;
  final List<String> artists;
  final int? year;
  final String? coverUrl;
  final int? trackCount;
  final int? downloadedCount;
  final List<Track>? tracks;
  final String? albumType;
  final String? releaseDate;

  Album({
    required this.id,
    required this.name,
    required this.artists,
    this.year,
    this.coverUrl,
    this.trackCount,
    this.downloadedCount,
    this.tracks,
    this.albumType,
    this.releaseDate,
  });

  String get displayBadge {
    final typeLabel = albumType != null && albumType!.isNotEmpty
        ? albumType!.toUpperCase()
        : 'ALBUM';
    final yearLabel = year != null
        ? ' • $year'
        : (releaseDate != null && releaseDate!.isNotEmpty
            ? ' • ${releaseDate!.split('-').first}'
            : '');
    return '$typeLabel$yearLabel';
  }

  factory Album.fromJson(Map<String, dynamic> json) {
    String albumId = (json['browse_id'] ?? json['id'] ?? '').toString().trim();
    if (albumId.isNotEmpty && RegExp(r'^\d+$').hasMatch(albumId)) {
      albumId = 'dz_$albumId';
    }

    List<String> artistsList = [];
    if (json['artists'] != null) {
      if (json['artists'] is List) {
        artistsList = (json['artists'] as List).map<String>((e) {
          if (e is Map && e.containsKey('name')) {
            return e['name'].toString();
          }
          return e.toString();
        }).toList();
      } else if (json['artists'] is String) {
        artistsList = [json['artists']];
      }
    }
    if (artistsList.isEmpty && json['artist_name'] != null) {
      artistsList = [json['artist_name'].toString()];
    }

    List<Track>? tracksList;
    if (json['tracks'] != null && json['tracks'] is List) {
      tracksList = (json['tracks'] as List)
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    int? parsedYear;
    if (json['year'] != null) {
      if (json['year'] is int) {
        parsedYear = json['year'];
      } else {
        parsedYear = int.tryParse(json['year'].toString());
      }
    }
    if (parsedYear == null && json['release_date'] != null) {
      final rDate = json['release_date'].toString();
      if (rDate.isNotEmpty) {
        parsedYear = int.tryParse(rDate.split('-').first);
      }
    }

    int? parsedTrackCount;
    final rawTrackCount = json['track_count'] ?? json['trackCount'];
    if (rawTrackCount != null) {
      if (rawTrackCount is int) {
        parsedTrackCount = rawTrackCount;
      } else {
        parsedTrackCount = int.tryParse(rawTrackCount.toString());
      }
    }
    parsedTrackCount ??= tracksList?.length;

    int? parsedDownloadedCount;
    if (json['downloaded_count'] != null) {
      parsedDownloadedCount = json['downloaded_count'] is int
          ? json['downloaded_count']
          : int.tryParse(json['downloaded_count'].toString());
    }

    return Album(
      id: albumId,
      name: (json['title'] ?? json['name'] ?? 'Unknown Album').toString(),
      artists: artistsList,
      year: parsedYear,
      coverUrl: (json['cover_url'] ?? json['album_art'] ?? json['albumArt'])?.toString(),
      trackCount: parsedTrackCount,
      downloadedCount: parsedDownloadedCount,
      tracks: tracksList,
      albumType: (json['album_type'] ?? json['albumType'] ?? json['type'])?.toString(),
      releaseDate: (json['release_date'] ?? json['releaseDate'])?.toString(),
    );
  }
}

class Artist {
  final String channelId;
  final String name;
  final String? description;
  final String? subscribers;
  final String? monthlyListeners;
  final int? fans;
  final int? albumCount;
  final String? coverUrl;
  final List<Track>? topSongs;
  final List<Album>? albums;
  final List<Album>? singles;

  Artist({
    required this.channelId,
    required this.name,
    this.description,
    this.subscribers,
    this.monthlyListeners,
    this.fans,
    this.albumCount,
    this.coverUrl,
    this.topSongs,
    this.albums,
    this.singles,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    String artistId = (json['channel_id'] ?? json['id'] ?? '').toString().trim();
    if (artistId.isNotEmpty && RegExp(r'^\d+$').hasMatch(artistId)) {
      artistId = 'dz_$artistId';
    }

    List<Track>? top;
    final rawTop = json['top_songs'] ?? json['top'];
    if (rawTop != null && rawTop is List) {
      top = (rawTop as List)
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    List<Album>? albs;
    if (json['albums'] != null && json['albums'] is List) {
      albs = (json['albums'] as List)
          .map((e) => Album.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    List<Album>? sngls;
    if (json['singles'] != null && json['singles'] is List) {
      sngls = (json['singles'] as List)
          .map((e) => Album.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return Artist(
      channelId: artistId,
      name: json['name'] ?? 'Unknown Artist',
      description: json['description'],
      subscribers: json['subscribers']?.toString(),
      monthlyListeners: json['monthly_listeners']?.toString(),
      fans: json['fans'] is int ? json['fans'] : int.tryParse(json['fans']?.toString() ?? ''),
      albumCount: json['album_count'] is int ? json['album_count'] : int.tryParse(json['album_count']?.toString() ?? ''),
      coverUrl: (json['cover_url'] ?? json['avatar_art'] ?? json['cover_path'])?.toString(),
      topSongs: top,
      albums: albs,
      singles: sngls,
    );
  }
}

class Playlist {
  final dynamic id; // String (e.g. "dz_90819" or "42")
  final int userId;
  final String name;
  final String? description;
  final String? ownerName;
  final String? coverPath;
  final String? coverUrl;
  final bool isPublic;
  final int? trackCount;
  final int? downloadedCount;
  final String? createdAt;
  final String? updatedAt;
  final List<Track>? tracks;

  Playlist({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    this.ownerName,
    this.coverPath,
    this.coverUrl,
    required this.isPublic,
    this.trackCount,
    this.downloadedCount,
    this.createdAt,
    this.updatedAt,
    this.tracks,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    String playlistId = (json['id'] ?? 0).toString().trim();
    if (playlistId.isNotEmpty && RegExp(r'^\d+$').hasMatch(playlistId) && json['owner_name'] == 'Deezer') {
      playlistId = 'dz_$playlistId';
    }

    List<Track>? tracksList;
    if (json['tracks'] != null && json['tracks'] is List) {
      tracksList = (json['tracks'] as List)
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    int? parsedTrackCount;
    final rawTrackCount = json['track_count'] ?? json['trackCount'];
    if (rawTrackCount != null) {
      if (rawTrackCount is int) {
        parsedTrackCount = rawTrackCount;
      } else {
        parsedTrackCount = int.tryParse(rawTrackCount.toString());
      }
    }
    parsedTrackCount ??= tracksList?.length;

    int? parsedDownloadedCount;
    if (json['downloaded_count'] != null) {
      parsedDownloadedCount = json['downloaded_count'] is int
          ? json['downloaded_count']
          : int.tryParse(json['downloaded_count'].toString());
    }

    return Playlist(
      id: playlistId,
      userId: json['user_id'] is int ? json['user_id'] : int.tryParse(json['user_id']?.toString() ?? '') ?? 0,
      name: (json['title'] ?? json['name'] ?? 'Unnamed Playlist').toString(),
      description: json['description']?.toString(),
      ownerName: json['owner_name']?.toString(),
      coverPath: json['cover_path']?.toString(),
      coverUrl: (json['cover_url'] ?? json['cover_path'])?.toString(),
      isPublic: json['is_public'] ?? false,
      trackCount: parsedTrackCount,
      downloadedCount: parsedDownloadedCount,
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      tracks: tracksList,
    );
  }
}

class HistoryEntry {
  final int id;
  final int userId;
  final String trackId;
  final DateTime listenedAt;
  final Track? track; // populated locally or from api

  HistoryEntry({
    required this.id,
    required this.userId,
    required this.trackId,
    required this.listenedAt,
    this.track,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json, {Track? enrichedTrack}) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['listened_at'] ?? json['listenedAt']);
    } catch (_) {
      parsedDate = DateTime.now();
    }
    final rawId = json['id'];
    final idVal = rawId is int ? rawId : (rawId != null ? int.tryParse(rawId.toString()) ?? 0 : 0);

    final rawUserId = json['user_id'] ?? json['userId'];
    final userIdVal = rawUserId is int ? rawUserId : (rawUserId != null ? int.tryParse(rawUserId.toString()) ?? 0 : 0);

    final trackIdVal = (json['track_id'] ?? json['trackId'] ?? json['video_id'] ?? '').toString();

    Track? trackVal = enrichedTrack;
    if (trackVal == null) {
      if (json['track'] != null) {
        trackVal = Track.fromJson(json['track']);
      } else if (json['video_id'] != null) {
        trackVal = Track.fromJson(json);
      }
    }

    return HistoryEntry(
      id: idVal,
      userId: userIdVal,
      trackId: trackIdVal,
      listenedAt: parsedDate,
      track: trackVal,
    );
  }
}

class ImportStatus {
  final String jobId;
  final String status;
  final int total;
  final int processed;
  final int queued;
  final int failed;
  final List<Map<String, dynamic>> failedTracks;
  final DateTime createdAt;

  ImportStatus({
    required this.jobId,
    required this.status,
    required this.total,
    required this.processed,
    required this.queued,
    required this.failed,
    required this.failedTracks,
    required this.createdAt,
  });

  factory ImportStatus.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> fails = [];
    if (json['failed_tracks'] != null && json['failed_tracks'] is List) {
      fails = (json['failed_tracks'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return ImportStatus(
      jobId: json['job_id'] ?? '',
      status: json['status'] ?? 'processing',
      total: json['total'] ?? 0,
      processed: json['processed'] ?? 0,
      queued: json['queued'] ?? 0,
      failed: json['failed'] ?? 0,
      failedTracks: fails,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }
}
