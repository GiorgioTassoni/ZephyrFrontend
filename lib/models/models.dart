class Track {
  final String videoId;
  final String title;
  final List<String> artists;
  final List<String> artistsIds;
  final String? album;
  final String? albumId;
  final Duration? duration;
  final String downloadStatus; // 'completed', 'pending', 'failed', 'downloading', 'not_in_db'
  final String? localPath;
  final String? localCoverPath;
  final String? coverUrl;
  final bool isDownloaded;
  final String? lyricsText;
  final String? lyricsLrc;

  Track({
    required this.videoId,
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
            if (id.isNotEmpty) artistsIdsList.add(id);
          } else if (e != null) {
            final s = e.toString().trim();
            if (s.isNotEmpty) artistsList.add(s);
          }
        }
      } else if (rawArtists is Map) {
        final name = (rawArtists['name'] ?? rawArtists['title'] ?? rawArtists['artist'] ?? '').toString().trim();
        final id = (rawArtists['id'] ?? rawArtists['channel_id'] ?? rawArtists['artist_id'] ?? rawArtists['browse_id'] ?? rawArtists['channelId'] ?? '').toString().trim();
        if (name.isNotEmpty) artistsList.add(name);
        if (id.isNotEmpty) artistsIdsList.add(id);
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

    // Filter out category labels (e.g. 'Song', 'Canzone', 'Video') incorrectly returned as artist names
    const invalidCategoryLabels = {'song', 'canzone', 'single', 'ep', 'video', 'track'};
    artistsList = artistsList.where((a) => !invalidCategoryLabels.contains(a.trim().toLowerCase())).toList();

    if (artistsIdsList.isEmpty) {
      if (json['artists_ids'] != null && json['artists_ids'] is List) {
        artistsIdsList = (json['artists_ids'] as List).map<String>((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      } else if (json['artist_ids'] != null && json['artist_ids'] is List) {
        artistsIdsList = (json['artist_ids'] as List).map<String>((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      } else if (json['channel_id'] != null && json['channel_id'].toString().trim().isNotEmpty) {
        artistsIdsList = [json['channel_id'].toString().trim()];
      } else if (json['artist_id'] != null && json['artist_id'].toString().trim().isNotEmpty) {
        artistsIdsList = [json['artist_id'].toString().trim()];
      }
    }

    // Determine duration
    Duration? trackDuration;
    if (json['duration'] != null) {
      if (json['duration'] is int) {
        trackDuration = Duration(seconds: json['duration']);
      } else if (json['duration'] is double) {
        trackDuration = Duration(seconds: (json['duration'] as double).toInt());
      } else if (json['duration'] is String) {
        final parts = (json['duration'] as String).split(':');
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

    // Determine download status
    String status = (json['download_status'] ?? 'not_in_db').toString();
    bool downloaded = json['is_downloaded'] ?? (status == 'completed');

    String vId = (json['video_id'] ?? json['id'] ?? json['videoId'] ?? '').toString();

    return Track(
      videoId: vId,
      title: (json['title'] ?? json['name'] ?? 'Unknown Track').toString(),
      artists: artistsList,
      artistsIds: artistsIdsList,
      album: json['album'] is String ? json['album'] : (json['album'] is Map ? json['album']['name']?.toString() : null),
      albumId: (json['album_id'] ?? json['albumId'])?.toString(),
      duration: trackDuration,
      downloadStatus: status,
      localPath: json['local_path']?.toString(),
      localCoverPath: json['local_cover_path']?.toString(),
      coverUrl: (json['cover_url'] ?? json['album_art'] ?? json['albumArt'])?.toString(),
      isDownloaded: downloaded,
      lyricsText: json['lyrics_text']?.toString(),
      lyricsLrc: json['lyrics_lrc']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'video_id': videoId,
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
    this.tracks,
    this.albumType,
    this.releaseDate,
  });

  String get displayBadge {
    final typeLabel = albumType != null && albumType!.isNotEmpty
        ? albumType!.toUpperCase()
        : 'ALBUM';
    final yearLabel = year != null ? ' • $year' : (releaseDate != null && releaseDate!.isNotEmpty ? ' • ${releaseDate!.split('-').first}' : '');
    return '$typeLabel$yearLabel';
  }

  factory Album.fromJson(Map<String, dynamic> json) {
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

    return Album(
      id: (json['browse_id'] ?? json['id'] ?? '').toString(),
      name: (json['title'] ?? json['name'] ?? 'Unknown Album').toString(),
      artists: artistsList,
      year: parsedYear,
      coverUrl: (json['cover_url'] ?? json['album_art'] ?? json['albumArt'])?.toString(),
      trackCount: parsedTrackCount,
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
    this.coverUrl,
    this.topSongs,
    this.albums,
    this.singles,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    List<Track>? top;
    if (json['top_songs'] != null && json['top_songs'] is List) {
      top = (json['top_songs'] as List)
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
      channelId: json['channel_id'] ?? json['id'] ?? '',
      name: json['name'] ?? 'Unknown Artist',
      description: json['description'],
      subscribers: json['subscribers'],
      monthlyListeners: json['monthly_listeners'],
      coverUrl: json['cover_url'] ?? json['avatar_art'] ?? json['cover_path'],
      topSongs: top,
      albums: albs,
      singles: sngls,
    );
  }
}

class Playlist {
  final int id;
  final int userId;
  final String name;
  final String? description;
  final String? coverPath;
  final bool isPublic;
  final String? createdAt;
  final String? updatedAt;
  final List<Track>? tracks;

  Playlist({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    this.coverPath,
    required this.isPublic,
    this.createdAt,
    this.updatedAt,
    this.tracks,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    List<Track>? tracksList;
    if (json['tracks'] != null && json['tracks'] is List) {
      tracksList = (json['tracks'] as List)
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return Playlist(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      name: json['name'] ?? 'Unnamed Playlist',
      description: json['description'],
      coverPath: json['cover_path'],
      isPublic: json['is_public'] ?? false,
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
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
