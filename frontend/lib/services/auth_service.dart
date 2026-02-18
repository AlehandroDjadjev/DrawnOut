import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized authentication service with automatic token refresh.
///
/// Stores both access and refresh JWT tokens. When an API call returns 401,
/// automatically attempts to refresh the access token using the refresh token.
/// If refresh fails, clears tokens and signals that the user must log in again.
class AuthService {
  static const String _accessTokenKey = 'token';
  static const String _refreshTokenKey = 'refresh_token';

  String _baseUrl;

  /// Callback invoked when the session is fully expired (refresh failed).
  /// The UI should navigate to the login page.
  void Function()? onSessionExpired;

  AuthService({String baseUrl = 'http://127.0.0.1:8000'})
      : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url.trim();
    if (_baseUrl.endsWith('/')) {
      _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
    }
  }

  String get baseUrl => _baseUrl;

  // ─────────────────────────────────────────────────────────────────────────
  // Token Storage
  // ─────────────────────────────────────────────────────────────────────────

  /// Store both access and refresh tokens after login/signup.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    debugPrint('🔑 Tokens saved');
  }

  /// Get the current access token (may be expired).
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// Get the current refresh token.
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  /// Check if any tokens are stored.
  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Clear all tokens (logout).
  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    debugPrint('🔑 Tokens cleared');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Token Refresh
  // ─────────────────────────────────────────────────────────────────────────

  /// Attempt to refresh the access token using the stored refresh token.
  /// Returns the new access token on success, null on failure.
  Future<String?> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      debugPrint('🔑 No refresh token available');
      return null;
    }

    try {
      debugPrint('🔑 Refreshing access token...');
      final uri = Uri.parse('$_baseUrl/api/auth/token/refresh/');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final newAccess = data['access'] as String?;
        final newRefresh = data['refresh'] as String?;

        if (newAccess != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_accessTokenKey, newAccess);
          // If server rotates refresh tokens, store the new one
          if (newRefresh != null) {
            await prefs.setString(_refreshTokenKey, newRefresh);
          }
          debugPrint('🔑 Token refreshed successfully');
          return newAccess;
        }
      }

      debugPrint('🔑 Token refresh failed: ${resp.statusCode}');
      return null;
    } catch (e) {
      debugPrint('🔑 Token refresh error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Authenticated HTTP Methods
  // ─────────────────────────────────────────────────────────────────────────

  /// Make an authenticated GET request with automatic token refresh.
  Future<http.Response> authenticatedGet(
    String url, {
    Map<String, String>? extraHeaders,
  }) async {
    return _authenticatedRequest('GET', url, extraHeaders: extraHeaders);
  }

  /// Make an authenticated POST request with automatic token refresh.
  Future<http.Response> authenticatedPost(
    String url, {
    Map<String, String>? extraHeaders,
    Object? body,
  }) async {
    return _authenticatedRequest('POST', url,
        extraHeaders: extraHeaders, body: body);
  }

  /// Make an authenticated PUT request with automatic token refresh.
  Future<http.Response> authenticatedPut(
    String url, {
    Map<String, String>? extraHeaders,
    Object? body,
  }) async {
    return _authenticatedRequest('PUT', url,
        extraHeaders: extraHeaders, body: body);
  }

  /// Make an authenticated PATCH request with automatic token refresh.
  Future<http.Response> authenticatedPatch(
    String url, {
    Map<String, String>? extraHeaders,
    Object? body,
  }) async {
    return _authenticatedRequest('PATCH', url,
        extraHeaders: extraHeaders, body: body);
  }

  /// Make an authenticated DELETE request with automatic token refresh.
  Future<http.Response> authenticatedDelete(
    String url, {
    Map<String, String>? extraHeaders,
    Object? body,
  }) async {
    return _authenticatedRequest('DELETE', url,
        extraHeaders: extraHeaders, body: body);
  }

  /// Internal: execute an HTTP request with auth, retrying once on 401.
  Future<http.Response> _authenticatedRequest(
    String method,
    String url, {
    Map<String, String>? extraHeaders,
    Object? body,
  }) async {
    var token = await getAccessToken();

    // First attempt
    var resp = await _executeRequest(method, url, token, extraHeaders, body);

    // If 401, try refreshing the token and retry once
    if (resp.statusCode == 401) {
      final newToken = await refreshAccessToken();
      if (newToken != null) {
        resp = await _executeRequest(method, url, newToken, extraHeaders, body);
      } else {
        // Refresh failed - session expired
        await clearTokens();
        onSessionExpired?.call();
      }
    }

    return resp;
  }

  Future<http.Response> _executeRequest(
    String method,
    String url,
    String? token,
    Map<String, String>? extraHeaders,
    Object? body,
  ) async {
    final uri = Uri.parse(url);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      ...?extraHeaders,
    };

    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        if (body != null) headers['Content-Type'] = 'application/json';
        return http.post(uri, headers: headers, body: body);
      case 'PUT':
        if (body != null) headers['Content-Type'] = 'application/json';
        return http.put(uri, headers: headers, body: body);
      case 'PATCH':
        if (body != null) headers['Content-Type'] = 'application/json';
        return http.patch(uri, headers: headers, body: body);
      case 'DELETE':
        return http.delete(uri, headers: headers, body: body);
      default:
        throw UnsupportedError('HTTP method $method not supported');
    }
  }
}
