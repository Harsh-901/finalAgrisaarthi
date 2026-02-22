import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/retry.dart';
import '../config/api_config.dart';

/// Service for communicating with the Django backend (AgriSarthi)
/// Uses Django JWT auth tokens (separate from Supabase auth)
class ApiService {
  // For production: https://agrisarthi.onrender.com
  // For local development on emulator: http://10.0.2.2:8000
  // For local development on physical device: use your computer's IP (e.g., http://192.168.1.5:8000)
  static String get baseUrl => ApiConfig.baseUrl;

  static const String _accessTokenKey = 'django_access_token';
  static const String _refreshTokenKey = 'django_refresh_token';
  static const String _farmerIdKey = 'django_farmer_id';

  String? _accessToken;
  String? _refreshToken;
  String? _djangoFarmerId;

  // Singleton
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _client = RetryClient(
      http.Client(),
      retries: 3,
      when: (response) =>
          response.statusCode == 503 ||
          response.statusCode == 502 ||
          response.statusCode == 504,
      onRetry: (req, resp, attempt) =>
          debugPrint('Retry attempt $attempt due to ${resp?.statusCode}'),
    );
  }

  late http.Client _client;

  /// Whether we have a Django auth token
  bool get isAuthenticated => _accessToken != null;
  String? get accessToken => _accessToken;
  String? get djangoFarmerId => _djangoFarmerId;

  /// Initialize - load saved tokens
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _djangoFarmerId = prefs.getString(_farmerIdKey);
    debugPrint('ApiService: Initialized. Has token: ${_accessToken != null}');
  }

  /// Save tokens locally
  Future<void> _saveTokens(
      String access, String refresh, String farmerId) async {
    _accessToken = access;
    _refreshToken = refresh;
    _djangoFarmerId = farmerId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, access);
    await prefs.setString(_refreshTokenKey, refresh);
    await prefs.setString(_farmerIdKey, farmerId);
  }

  /// Clear saved tokens
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _djangoFarmerId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_farmerIdKey);
  }

  /// Ping the server to wake it up (handles Render cold starts).
  /// Call this early (e.g., on app start or before auth flow).
  Future<bool> pingServer() async {
    try {
      debugPrint('ApiService: Pinging server to wake up Render dyno...');
      final response = await _client.get(
        Uri.parse('$baseUrl/api/health/'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 120)); // Long timeout for cold start
      final isOk = response.statusCode == 200;
      debugPrint(
          'ApiService: Server ping ${isOk ? "✅ OK" : "❌ FAILED (${response.statusCode})"}');
      return isOk;
    } catch (e) {
      debugPrint('ApiService: Server ping error: $e');
      return false;
    }
  }

  /// Login to Django backend using phone + OTP
  /// Step 1: Send OTP
  /// NOTE: Render free tier can take 30-90s to cold start. Timeout is set to 120s.
  Future<Map<String, dynamic>> sendDjangoOtp(String phone) async {
    try {
      debugPrint('ApiService: Sending OTP to $phone...');
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/auth/login/'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'phone': phone}),
          )
          .timeout(
              const Duration(seconds: 120)); // Long timeout for cold starts

      debugPrint('ApiService: sendOTP status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('ApiService: Send OTP success');
        return data;
      } else {
        debugPrint('ApiService: Error body: ${response.body}');
        return {
          'success': false,
          'message': 'Server error (${response.statusCode}). Please try again.'
        };
      }
    } on Exception catch (e) {
      final errStr = e.toString();
      if (errStr.contains('TimeoutException') || errStr.contains('timed out')) {
        debugPrint('ApiService: Send OTP TIMEOUT (server cold start): $e');
        return {
          'success': false,
          'message': 'Server is starting up. Please retry in a moment.'
        };
      }
      debugPrint('ApiService: Send OTP error: $e');
      return {
        'success': false,
        'message': 'Connection error. Check your internet connection.'
      };
    }
  }

  /// Login to Django backend using phone + OTP
  /// Step 2: Verify OTP and get tokens
  Future<Map<String, dynamic>> verifyDjangoOtp(String phone, String otp) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/auth/verify/'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'phone': phone, 'otp': otp}),
          )
          .timeout(
              const Duration(seconds: 30)); // Server already warm at this point

      debugPrint('ApiService: verifyOTP status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('ApiService: Verify OTP success: ${data['success']}');

        if (data['success'] == true && data['data'] != null) {
          await _saveTokens(
            data['data']['access_token'],
            data['data']['refresh_token'],
            data['data']['farmer_id'],
          );
        }
        return data;
      } else {
        debugPrint('ApiService: Verify OTP error body: ${response.body}');
        return {
          'success': false,
          'message': 'OTP verification failed (${response.statusCode})'
        };
      }
    } catch (e) {
      debugPrint('ApiService: Verify OTP error: $e');
      return {
        'success': false,
        'message': 'Connection error during verification. Please retry.'
      };
    }
  }

  /// Refresh the access token
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/auth/refresh/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': _refreshToken}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          _accessToken = data['data']['access_token'];
          _refreshToken = data['data']['refresh_token'];

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_accessTokenKey, _accessToken!);
          await prefs.setString(_refreshTokenKey, _refreshToken!);
          return true;
        }
      }
    } catch (e) {
      debugPrint('ApiService: Token refresh error: $e');
    }
    return false;
  }

  /// Make authenticated GET request to Django
  Future<Map<String, dynamic>> get(String endpoint) async {
    if (_accessToken == null) {
      return {'success': false, 'message': 'Not authenticated with server'};
    }

    try {
      var response = await _client.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
      ).timeout(const Duration(seconds: 60));

      // If 401, try refreshing token
      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          response = await _client.get(
            Uri.parse('$baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_accessToken',
            },
          ).timeout(const Duration(seconds: 60));
        } else {
          return {
            'success': false,
            'message': 'Session expired. Please re-login.'
          };
        }
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('ApiService: GET $endpoint error: $e');
      return {'success': false, 'message': 'Connection error or timeout'};
    }
  }

  /// Make authenticated POST request to Django
  Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    if (_accessToken == null) {
      return {'success': false, 'message': 'Not authenticated with server'};
    }

    try {
      var response = await _client
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      // If 401, try refreshing token
      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          response = await _client
              .post(
                Uri.parse('$baseUrl$endpoint'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $_accessToken',
                },
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 60));
        } else {
          return {
            'success': false,
            'message': 'Session expired. Please re-login.'
          };
        }
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('ApiService: POST $endpoint error: $e');
      return {'success': false, 'message': 'Connection error or timeout'};
    }
  }
}
