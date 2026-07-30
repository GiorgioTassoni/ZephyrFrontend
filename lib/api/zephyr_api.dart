import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ZephyrApi {
  late Dio _dio;
  String _baseUrl = 'http://localhost:8000';
  String? _token;        // short-lived access token (JWT, 15 min)
  String? _refreshToken; // long-lived refresh token (opaque, 14 days)
  void Function()? onUnauthorized;
  void Function(String token)? onTokenRefreshed;

  // Local proxy server for audio streaming (injects Authorization header
  // so audioplayers never has to embed the token in the URL — S-03 compliance).
  HttpServer? _proxyServer;
  int _proxyPort = 0;

  static final ZephyrApi _instance = ZephyrApi._internal();

  factory ZephyrApi() {
    return _instance;
  }

  ZephyrApi._internal() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null && !options.headers.containsKey('Authorization')) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onError: (e, handler) async {
        // On 401, attempt a single token refresh then retry.
        // If the refresh itself fails, signal onUnauthorized — no re-login.
        if (e.response?.statusCode == 401 &&
            !e.requestOptions.path.contains('/api/auth/login') &&
            !e.requestOptions.path.contains('/api/auth/refresh') &&
            !e.requestOptions.path.contains('/api/auth/logout')) {

          final didRefresh = await _tryRefresh();
          if (didRefresh) {
            e.requestOptions.headers['Authorization'] = 'Bearer $_token';
            try {
              final response = await _dio.fetch(e.requestOptions);
              return handler.resolve(response);
            } catch (_) {
              return handler.next(e);
            }
          } else {
            onUnauthorized?.call();
          }
        }
        return handler.next(e);
      },
    ));
    _loadSettings();
  }

  Future<bool>? _refreshFuture;

  /// Rotate the refresh token and mint a new access + refresh pair.
  /// Uses a single-flight Future so concurrent 401s share the same refresh attempt.
  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;
    if (_refreshFuture != null) {
      return _refreshFuture!;
    }

    _refreshFuture = _executeRefresh();
    try {
      return await _refreshFuture!;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<bool> _executeRefresh() async {
    try {
      final response = await _dio.post(
        '/api/auth/refresh',
        options: Options(
          headers: {'Authorization': 'Bearer $_refreshToken'},
        ),
      );
      final data = response.data;
      if (data['access_token'] != null && data['refresh_token'] != null) {
        final newAccess = data['access_token'] as String;
        await setTokens(
          accessToken: newAccess,
          refreshToken: data['refresh_token'] as String,
        );
        onTokenRefreshed?.call(newAccess);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String get baseUrl => _baseUrl;
  String? get token => _token;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('zephyr_server_url') ?? 'http://localhost:8000';
    _token = prefs.getString('zephyr_auth_token');
    _refreshToken = prefs.getString('zephyr_refresh_token');
    _dio.options.baseUrl = _baseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    _baseUrl = cleanUrl;
    _dio.options.baseUrl = _baseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zephyr_server_url', _baseUrl);
  }

  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _token = accessToken;
    _refreshToken = refreshToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zephyr_auth_token', accessToken);
    await prefs.setString('zephyr_refresh_token', refreshToken);
  }

  Future<void> clearAuth() async {
    _token = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zephyr_auth_token');
    await prefs.remove('zephyr_refresh_token');
  }

  // --- Auth ---

  Future<Map<String, dynamic>> register(String username, String password) async {
    try {
      final response = await _dio.post('/api/auth/register', data: {
        'username': username,
        'password': password,
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _dio.post(
        '/api/auth/login',
        data: 'username=$username&password=$password',
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = response.data;
      if (data['access_token'] != null && data['refresh_token'] != null) {
        await setTokens(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
        );
      }
      return data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Call the server logout endpoint (invalidates the refresh token server-side),
  /// then wipe local credentials.
  Future<void> logout() async {
    if (_refreshToken != null) {
      try {
        await _dio.post(
          '/api/auth/logout',
          options: Options(
            headers: {'Authorization': 'Bearer $_refreshToken'},
          ),
        );
      } catch (_) {
        // Best-effort — clear locally regardless
      }
    }
    await clearAuth();
  }

  // --- Search ---

  Future<Map<String, dynamic>> search(String query, {bool remote = false}) async {
    try {
      final response = await _dio.get('/api/search', queryParameters: {
        'q': query,
        'remote': remote.toString(),
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Tracks ---

  /// Returns a proxy URL (localhost) for the audio player so that the
  /// actual Authorization header is injected by our local proxy — never
  /// embedded as a query parameter (S-03 compliance).
  Future<String> getStreamProxyUrl(String videoId) async {
    if (_proxyServer == null) {
      await _startProxyServer();
    }
    return 'http://localhost:$_proxyPort/stream/$videoId';
  }

  /// Starts a lightweight local HTTP proxy on a random port.
  /// Intercepts /stream/<videoId> requests and forwards them to the
  /// backend with the Authorization header injected.
  Future<void> _startProxyServer() async {
    _proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _proxyPort = _proxyServer!.port;
    _proxyServer!.listen((HttpRequest req) async {
      final videoId = req.uri.pathSegments.length >= 2
          ? req.uri.pathSegments.last
          : '';
      final backendUrl = Uri.parse('$_baseUrl/api/tracks/stream/$videoId');

      try {
        final client = HttpClient();
        final backendReq = await client.getUrl(backendUrl);
        if (_token != null) {
          backendReq.headers.set('Authorization', 'Bearer $_token');
        }
        // Forward Range header from audioplayers if present
        final rangeHeader = req.headers.value('range');
        if (rangeHeader != null) {
          backendReq.headers.set('range', rangeHeader);
        }
        final backendResp = await backendReq.close();

        req.response.statusCode = backendResp.statusCode;
        backendResp.headers.forEach((name, values) {
          try {
            req.response.headers.set(name, values.join(','));
          } catch (_) {}
        });
        await backendResp.pipe(req.response);
        client.close();
      } catch (e) {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      }
    });
  }

  /// Stop the proxy (call on app dispose if needed).
  Future<void> stopProxyServer() async {
    await _proxyServer?.close(force: true);
    _proxyServer = null;
    _proxyPort = 0;
  }

  /// Cover image URL — token is injected via Authorization header by
  /// CachedNetworkImage's httpHeaders, never in the URL (S-03 compliance).
  String getCoverUrl(String videoId) {
    return '$_baseUrl/api/tracks/cover/$videoId';
  }

  Future<Map<String, dynamic>> queueDownload(String videoId) async {
    try {
      final response = await _dio.post('/api/tracks/download/$videoId');
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<List<Track>> getDownloadedTracks() async {
    try {
      final response = await _dio.get('/api/tracks');
      final List tracksList = response.data['tracks'] ?? [];
      return tracksList.map((e) => Track.fromJson(e)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Track> getTrackMetadata(String videoId) async {
    try {
      final response = await _dio.get('/api/tracks/$videoId');
      return Track.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> getTrackAlbum(String trackId) async {
    try {
      final response = await _dio.get('/api/tracks/$trackId/album');
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> getRelatedTracks(String videoId) async {
    try {
      final response = await _dio.get('/api/tracks/$videoId/related');
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Albums & Artists ---

  Future<Album> getAlbumDetail(String browseId, {bool refresh = false}) async {
    try {
      final response = await _dio.get('/api/albums/$browseId', queryParameters: {
        'refresh': refresh.toString(),
      });
      return Album.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Artist> getArtistDetail(String channelId) async {
    try {
      final response = await _dio.get('/api/artists/$channelId');
      return Artist.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> downloadAlbum(String browseId) async {
    try {
      final response = await _dio.post('/api/albums/download/$browseId');
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Favorites ---

  Future<List<Track>> getFavorites({int offset = 0}) async {
    try {
      final response = await _dio.get('/api/favorites', queryParameters: {'offset': offset});
      final List list = response.data;
      return list.map((e) => Track.fromJson(e)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<bool> isFavorite(String trackId) async {
    try {
      final response = await _dio.get('/api/favorites/$trackId');
      return response.data['is_favorite'] ?? false;
    } on DioException catch (e) {
      // If it fails, return false
      return false;
    }
  }

  Future<void> addFavorite(String trackId) async {
    try {
      await _dio.post('/api/favorites/$trackId');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> removeFavorite(String trackId) async {
    try {
      await _dio.delete('/api/favorites/$trackId');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Playlists ---

  Future<List<Playlist>> getPlaylists() async {
    try {
      final response = await _dio.get('/api/playlists');
      final List list = response.data;
      return list.map((e) => Playlist.fromJson(e)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Playlist> getPlaylistDetail(int id) async {
    try {
      final response = await _dio.get('/api/playlists/$id');
      return Playlist.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Playlist> createPlaylist(String name, String description, bool isPublic) async {
    try {
      final response = await _dio.post('/api/playlists', data: {
        'name': name,
        'description': description,
        'is_public': isPublic,
      });
      final playlistId = response.data['playlist_id'];
      return Playlist(
        id: playlistId,
        userId: 0, // Server will resolve ownership
        name: name,
        description: description,
        isPublic: isPublic,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> updatePlaylist(int id, {String? name, String? description, bool? isPublic}) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (description != null) data['description'] = description;
      if (isPublic != null) data['is_public'] = isPublic;

      await _dio.put('/api/playlists/$id', data: data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> deletePlaylist(int id) async {
    try {
      await _dio.delete('/api/playlists/$id');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<String> uploadPlaylistCover(int id, File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      });
      final response = await _dio.post(
        '/api/playlists/$id/cover',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return response.data['cover_url'] ?? '';
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  String getPlaylistCoverUrl(int id) {
    // Token is sent via Authorization header; never embed in URL (S-03).
    return '$_baseUrl/api/playlists/$id/cover';
  }

  // --- Password Change (S-07) ---

  /// POST /api/auth/change-password
  /// Returns the response body on 200; throws a descriptive String on error.
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/change-password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      return response.data ?? {};
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> addTrackToPlaylist(int playlistId, String trackId) async {
    try {
      await _dio.post('/api/playlists/$playlistId/tracks', data: {
        'track_id': trackId,
      });
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> removeTrackFromPlaylist(int playlistId, String trackId) async {
    try {
      await _dio.delete('/api/playlists/$playlistId/tracks', data: {
        'track_id': trackId,
      });
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> reorderPlaylistTracks(int playlistId, List<String> newOrder) async {
    try {
      await _dio.put('/api/playlists/$playlistId/tracks/reorder', data: {
        'new_order': newOrder,
      });
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Listening History ---

  Future<void> recordListen(String trackId) async {
    try {
      await _dio.post('/api/history', data: {
        'track_id': trackId,
      });
    } on DioException catch (_) {
      // Silent error for history
    }
  }

  Future<List<HistoryEntry>> getHistory() async {
    try {
      final response = await _dio.get('/api/history');
      final List list = response.data['records'] ?? [];
      return list.map((e) => HistoryEntry.fromJson(e)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Admin ---

  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await _dio.get('/api/admin/users');
      final List list = response.data['users'] ?? [];
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getPendingUsers() async {
    try {
      final response = await _dio.get('/api/admin/users/pending');
      final List list = response.data['pending_users'] ?? [];
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> approveUser(String username) async {
    try {
      await _dio.post('/api/admin/users/$username/approve');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- CSV Import ---

  Future<ImportStatus> importCsv(File csvFile) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          csvFile.path,
          filename: csvFile.path.split('/').last,
        ),
      });
      final response = await _dio.post(
        '/api/import/csv',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return ImportStatus(
        jobId: response.data['job_id'] ?? '',
        status: response.data['status'] ?? 'processing',
        total: response.data['total'] ?? 0,
        processed: 0,
        queued: 0,
        failed: 0,
        failedTracks: [],
        createdAt: DateTime.now(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<ImportStatus> getImportStatus(String jobId) async {
    try {
      final response = await _dio.get('/api/import/status/$jobId');
      return ImportStatus.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Statistics ---

  Future<Map<String, dynamic>> getHistoryStatistics(String period) async {
    try {
      final response = await _dio.get(
        '/api/history/statistics',
        queryParameters: {'period': period},
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Curator Promotion & Advanced Admin ---

  Future<void> promoteToCurator(String username) async {
    try {
      await _dio.post('/api/admin/curator/$username');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> getAdminStats() async {
    try {
      final response = await _dio.get('/api/admin/stats');
      return response.data['stats'] ?? {};
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> getOrphans() async {
    try {
      final response = await _dio.get('/api/admin/orphans');
      return response.data['orphans'] ?? {};
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<int> retryFailedDownloads() async {
    try {
      final response = await _dio.post('/api/admin/retry-failed');
      return response.data['retried_count'] ?? 0;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> deleteTrack(String trackId) async {
    try {
      await _dio.delete('/api/admin/tracks/$trackId');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Local Catalog Listings ---

  Future<List<Map<String, dynamic>>> getLocalArtists() async {
    try {
      final response = await _dio.get('/api/artists/local');
      final List list = response.data['artists'] ?? [];
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> getArtistByName(String name) async {
    try {
      final response = await _dio.get('/api/artists/by-name/$name');
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> getArtistsDirectory({int limit = 100, int offset = 0}) async {
    try {
      final response = await _dio.get(
        '/api/artists/directory',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getLocalAlbums() async {
    try {
      final response = await _dio.get('/api/albums/local');
      final List list = response.data['albums'] ?? [];
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> getLocalArtistDetails(String artistId) async {
    try {
      final response = await _dio.get('/api/artists/local/$artistId');
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Curator Track/Artist/Album Creation & Updates ---

  Future<Map<String, dynamic>> uploadTrack({
    required File file,
    required String title,
    required String artists,
    String? album,
    int? duration,
  }) async {
    try {
      final Map<String, dynamic> formMap = {
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
        'title': title,
        'artists': artists,
      };
      if (album != null) formMap['album'] = album;
      if (duration != null) formMap['duration'] = duration;

      final formData = FormData.fromMap(formMap);
      final response = await _dio.post(
        '/api/curator/tracks/upload',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> updateTrackMetadata(
    String trackId, {
    String? title,
    List<String>? artistIds,
    String? album,
    String? albumId,
    String? lyrics,
    String? lyricsLrc,
  }) async {
    try {
      final Map<String, dynamic> body = {};
      if (title != null) body['title'] = title;
      if (artistIds != null) body['artist_ids'] = artistIds;
      if (album != null) body['album'] = album;
      if (albumId != null) body['album_id'] = albumId;
      if (lyrics != null) body['lyrics'] = lyrics;
      if (lyricsLrc != null) body['lyrics_lrc'] = lyricsLrc;

      await _dio.put(
        '/api/curator/tracks/$trackId',
        data: body,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> uploadTrackCover(String trackId, File file) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
      });
      await _dio.post(
        '/api/curator/tracks/$trackId/cover',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> createLocalAlbum({
    required String title,
    required List<String> artistIds,
    required int year,
    required List<String> trackIds,
  }) async {
    try {
      final response = await _dio.post(
        '/api/curator/albums',
        data: {
          'title': title,
          'artist_ids': artistIds,
          'year': year,
          'track_ids': trackIds,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> uploadAlbumCover(String browseId, File file) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
      });
      await _dio.post(
        '/api/curator/albums/$browseId/cover',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> createLocalArtist({
    required String name,
    String? bio,
  }) async {
    try {
      final response = await _dio.post(
        '/api/curator/artists',
        data: {
          'name': name,
          'bio': bio,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> uploadArtistCover(String artistId, File file) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
      });
      await _dio.post(
        '/api/curator/artists/$artistId/cover',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // --- Error Handling ---

  String _handleDioError(DioException error) {
    if (error.response != null) {
      final data = error.response?.data;
      if (data is Map) {
        if (data.containsKey('missing_ids')) {
          final missing = (data['missing_ids'] as List).join(', ');
          return 'Artist not found: Unknown artist ID(s): $missing';
        }
        if (data.containsKey('detail')) {
          return data['detail'].toString();
        }
        if (data.containsKey('message')) {
          return data['message'].toString();
        }
      }
      return 'Error: ${error.response?.statusCode} - ${error.response?.statusMessage}';
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout';
      case DioExceptionType.sendTimeout:
        return 'Send timeout';
      case DioExceptionType.receiveTimeout:
        return 'Receive timeout';
      case DioExceptionType.connectionError:
        return 'Failed to connect to Zephyr server. Make sure base URL is correct.';
      default:
        return error.message ?? 'Unknown network error';
    }
  }
}
