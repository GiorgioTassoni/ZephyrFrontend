import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/zephyr_api.dart';

class AuthState {
  final String? token;
  final String? username;
  final String role; // 'user' | 'curator' | 'admin'
  final bool isApproved;
  final bool isLoading;
  final String? errorMessage;
  /// S-07: Set to true when the backend requires the user to rotate their
  /// password before any protected endpoint will accept them.
  final bool mustChangePassword;

  AuthState({
    this.token,
    this.username,
    this.role = 'user',
    this.isApproved = false,
    this.isLoading = false,
    this.errorMessage,
    this.mustChangePassword = false,
  });

  bool get isAuthenticated => token != null && isApproved;
  bool get isAdmin => role == 'admin';
  bool get isCurator => role == 'curator' || role == 'admin';

  AuthState copyWith({
    String? token,
    String? username,
    String? role,
    bool? isApproved,
    bool? isLoading,
    String? errorMessage,
    bool? mustChangePassword,
  }) {
    return AuthState(
      token: token ?? this.token,
      username: username ?? this.username,
      role: role ?? this.role,
      isApproved: isApproved ?? this.isApproved,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  final ZephyrApi _api = ZephyrApi();
  Timer? _refreshTimer;

  @override
  AuthState build() {
    // Clear initially. Will only be bound when a session is actively authenticated.
    _api.onUnauthorized = null;
    _api.onTokenRefreshed = (newToken) {
      state = state.copyWith(token: newToken);
      _scheduleProactiveRefresh(newToken);
    };
    Future.microtask(() => tryAutoLogin());
    return AuthState(isLoading: true);
  }

  void _scheduleProactiveRefresh(String? token) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (token == null || token.isEmpty) return;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      final exp = payload['exp'];
      if (exp is num) {
        final expDate = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
        final nowUtc = DateTime.now().toUtc();
        // Refresh 2 minutes before expiration (or immediately if less than 2 mins left)
        final refreshDate = expDate.subtract(const Duration(minutes: 2));
        final diff = refreshDate.difference(nowUtc);
        final waitDuration = diff.isNegative ? Duration.zero : diff;
        _refreshTimer = Timer(waitDuration, () async {
          final success = await _api.refreshToken();
          if (success && state.isAuthenticated) {
            _scheduleProactiveRefresh(_api.token);
          }
        });
      }
    } catch (_) {}
  }

  bool _isTokenExpired(String? token, {int bufferSeconds = 60}) {
    if (token == null || token.isEmpty) return true;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      final exp = payload['exp'];
      if (exp is num) {
        final expDate = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
        final nowUtc = DateTime.now().toUtc();
        return nowUtc.add(Duration(seconds: bufferSeconds)).isAfter(expDate);
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// On startup: restore the stored access token.
  /// If it's expired, proactively refresh it using the refresh token
  /// BEFORE rendering views or making regular API requests.
  Future<void> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('zephyr_auth_token');
    final username = prefs.getString('zephyr_username');
    final role = prefs.getString('zephyr_role') ??
        (prefs.getBool('zephyr_is_admin') == true ? 'admin' : 'user');
    final isApproved = prefs.getBool('zephyr_is_approved') ?? false;

    if (token != null && isApproved) {
      final refreshToken = prefs.getString('zephyr_refresh_token');
      if (refreshToken != null) {
        await _api.setTokens(accessToken: token, refreshToken: refreshToken);
      }

      // Check if access token is already expired from a previous session
      if (_isTokenExpired(token) && refreshToken != null) {
        final refreshed = await _api.refreshToken();
        if (!refreshed) {
          state = AuthState(isLoading: false);
          return;
        }
      }

      // Optimistic session restore: the token is present and either still
      // valid or was freshly refreshed above. Skip the dedicated validation
      // round trip (it duplicated the first library request and delayed every
      // startup by one full RTT) and let the first real API call validate
      // server-side — a dead session hits the interceptor's 401 path, fails
      // to refresh, and lands in forceLogout().
      _api.onUnauthorized = () {
        forceLogout('New session detected, disconnected');
      };

      final effectiveToken = _api.token ?? token;
      _scheduleProactiveRefresh(effectiveToken);

      state = AuthState(
        token: effectiveToken,
        username: username,
        role: role,
        isApproved: isApproved,
        isLoading: false,
      );
      return;
    }

    state = AuthState(isLoading: false);
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _api.login(username, password);
      final token = res['access_token'];
      final approved = res['is_approved'] ?? false;
      final role =
          res['role'] ?? (res['is_admin'] == true ? 'admin' : 'user');
      // S-07: check forced password rotation flag
      final mustChangePwd = res['must_change_password'] == true;

      if (!approved) {
        state = AuthState(
          errorMessage: 'Your account is pending admin approval.',
          isLoading: false,
        );
        return false;
      }

      // Persist session metadata (tokens are saved by _api.login → setTokens)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zephyr_username', username);
      await prefs.setString('zephyr_role', role);
      await prefs.setBool('zephyr_is_admin', role == 'admin');
      await prefs.setBool('zephyr_is_approved', approved);

      // Bind callback on successful login
      _api.onUnauthorized = () {
        forceLogout('New session detected, disconnected');
      };

      if (token != null) {
        _scheduleProactiveRefresh(token as String);
      }

      state = AuthState(
        token: token,
        username: username,
        role: role,
        isApproved: approved,
        isLoading: false,
        mustChangePassword: mustChangePwd,
      );
      return true;
    } catch (e) {
      state = AuthState(
        errorMessage: e.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  Future<String?> register(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _api.register(username, password);
      state = AuthState(isLoading: false);
      return res['message'] ??
          'Registration successful. Wait for admin approval.';
    } catch (e) {
      state = AuthState(
        errorMessage: e.toString(),
        isLoading: false,
      );
      return null;
    }
  }

  Future<void> logout() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _api.onUnauthorized = null; // Unbind callback so pending requests cannot trigger forceLogout
    state = state.copyWith(isLoading: true);

    // Tell the server to invalidate the refresh token (best-effort)
    await _api.logout();

    // Clear all local session data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zephyr_auth_token');
    await prefs.remove('zephyr_refresh_token');
    await prefs.remove('zephyr_username');
    await prefs.remove('zephyr_is_admin');
    await prefs.remove('zephyr_role');
    await prefs.remove('zephyr_is_approved');

    state = AuthState(isLoading: false);
  }

  Future<void> forceLogout(String message) async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _api.onUnauthorized = null; // Unbind callback to avoid duplicate triggers
    state = state.copyWith(isLoading: true);

    // Clear tokens locally without calling the API logout (session is already invalid)
    await _api.clearAuth();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zephyr_auth_token');
    await prefs.remove('zephyr_refresh_token');
    await prefs.remove('zephyr_is_admin');
    await prefs.remove('zephyr_role');
    await prefs.remove('zephyr_is_approved');

    state = AuthState(
      errorMessage: message,
      isLoading: false,
    );
  }

  Future<void> updateServerUrl(String url) async {
    await _api.setBaseUrl(url);
  }

  // --- S-07: Forced password rotation ---

  /// Submit a password change. On success the backend wipes the entire
  /// session family, so we clear local tokens and force a re-login.
  /// Returns null on success or an error message string.
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _api.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      // Session wiped server-side — clear everything locally too
      await _api.clearAuth();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('zephyr_auth_token');
      await prefs.remove('zephyr_refresh_token');
      await prefs.remove('zephyr_username');
      await prefs.remove('zephyr_is_admin');
      await prefs.remove('zephyr_role');
      await prefs.remove('zephyr_is_approved');
      state = AuthState(isLoading: false); // back to login screen
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

final authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
