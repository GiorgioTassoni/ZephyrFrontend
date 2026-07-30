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

  @override
  AuthState build() {
    print("[AuthNotifier] build() initialized.");
    // Clear initially. Will only be bound when a session is actively authenticated.
    _api.onUnauthorized = null;
    _api.onTokenRefreshed = (newToken) {
      print("[AuthNotifier] onTokenRefreshed: Token updated reactively.");
      state = state.copyWith(token: newToken);
    };
    Future.microtask(() => tryAutoLogin());
    return AuthState(isLoading: true);
  }

  /// On startup: restore the stored access token.
  /// If it's expired, the Dio interceptor will silently refresh it using
  /// the stored refresh token on the first API call.
  Future<void> tryAutoLogin() async {
    print("[AuthNotifier] tryAutoLogin() started.");
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('zephyr_auth_token');
    final username = prefs.getString('zephyr_username');
    final role = prefs.getString('zephyr_role') ??
        (prefs.getBool('zephyr_is_admin') == true ? 'admin' : 'user');
    final isApproved = prefs.getBool('zephyr_is_approved') ?? false;

    if (token != null && isApproved) {
      print("[AuthNotifier] Cached token found: $token");
      // Restore tokens into the API singleton so the interceptor can use them
      final refreshToken = prefs.getString('zephyr_refresh_token');
      if (refreshToken != null) {
        await _api.setTokens(
            accessToken: token, refreshToken: refreshToken);
      }

      // Validate with a lightweight call; the interceptor auto-refreshes if needed
      try {
        print("[AuthNotifier] Validating cached token against /api/favorites...");
        await _api.getFavorites();

        // Bind callback on successful session validation
        _api.onUnauthorized = () {
          print("[AuthNotifier] onUnauthorized callback triggered via tryAutoLogin session.");
          forceLogout('New session detected, disconnected');
        };

        print("[AuthNotifier] Cached token valid. Auto-login successful.");
        state = AuthState(
          token: _api.token ?? token,
          username: username,
          role: role,
          isApproved: isApproved,
          isLoading: false,
        );
        return;
      } catch (e) {
        print("[AuthNotifier] Validating cached token failed: $e");
        // Token + refresh both invalid — fall through to unauthenticated
      }
    } else {
      print("[AuthNotifier] No cached session tokens found.");
    }

    print("[AuthNotifier] tryAutoLogin completed: unauthenticated.");
    state = AuthState(isLoading: false);
  }

  Future<bool> login(String username, String password) async {
    print("[AuthNotifier] login() initiated for user: $username");
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
        print("[AuthNotifier] Login failed: pending admin approval.");
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
        print("[AuthNotifier] onUnauthorized callback triggered via login session.");
        forceLogout('New session detected, disconnected');
      };

      print("[AuthNotifier] Login successful. mustChangePassword=$mustChangePwd");
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
      print("[AuthNotifier] Login failed with exception: $e");
      state = AuthState(
        errorMessage: e.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  Future<String?> register(String username, String password) async {
    print("[AuthNotifier] register() initiated for user: $username");
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _api.register(username, password);
      state = AuthState(isLoading: false);
      print("[AuthNotifier] Registration API success.");
      return res['message'] ??
          'Registration successful. Wait for admin approval.';
    } catch (e) {
      print("[AuthNotifier] Registration failed: $e");
      state = AuthState(
        errorMessage: e.toString(),
        isLoading: false,
      );
      return null;
    }
  }

  Future<void> logout() async {
    print("[AuthNotifier] Manual logout() initiated.");
    _api.onUnauthorized = null; // Unbind callback so pending requests cannot trigger forceLogout
    state = state.copyWith(isLoading: true);

    // Tell the server to invalidate the refresh token (best-effort)
    print("[AuthNotifier] Calling API logout...");
    await _api.logout();

    // Clear all local session data
    print("[AuthNotifier] Wiping local session preferences...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zephyr_auth_token');
    await prefs.remove('zephyr_refresh_token');
    await prefs.remove('zephyr_username');
    await prefs.remove('zephyr_is_admin');
    await prefs.remove('zephyr_role');
    await prefs.remove('zephyr_is_approved');

    print("[AuthNotifier] Manual logout completed. Error message is null.");
    state = AuthState(isLoading: false);
  }

  Future<void> forceLogout(String message) async {
    print("[AuthNotifier] forceLogout() initiated with message: $message");
    _api.onUnauthorized = null; // Unbind callback to avoid duplicate triggers
    state = state.copyWith(isLoading: true);

    // Clear tokens locally without calling the API logout (session is already invalid)
    print("[AuthNotifier] Clearing local authentication tokens...");
    await _api.clearAuth();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zephyr_auth_token');
    await prefs.remove('zephyr_refresh_token');
    await prefs.remove('zephyr_is_admin');
    await prefs.remove('zephyr_role');
    await prefs.remove('zephyr_is_approved');

    print("[AuthNotifier] Force logout completed. State updated with warning.");
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
