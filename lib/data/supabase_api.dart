import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/supabase_config.dart';

enum AuthStatus { ok, wrongDetails, phoneExists, emailExists, notConfigured, network, server }

/// What came back from a Supabase function call.
class ApiResponse {
  final bool ok;
  final dynamic json;
  final AuthStatus status;
  final String message;
  const ApiResponse.success(this.json)
      : ok = true,
        status = AuthStatus.ok,
        message = '';
  const ApiResponse.failure(this.status, this.message)
      : ok = false,
        json = null;
}

/// Calls the SQL functions from supabase/setup.sql through Supabase's REST API.
/// Uses only dart:io, so it adds no native code to the app.
class SupabaseApi {
  static Future<ApiResponse> rpc(String fn, Map<String, dynamic> body) async {
    if (!SupabaseConfig.isConfigured) {
      return const ApiResponse.failure(
        AuthStatus.notConfigured,
        'Database not connected yet. Add your Supabase URL and key in lib/config/supabase_config.dart.',
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse('${SupabaseConfig.baseUrl}/rest/v1/rpc/$fn');
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set('apikey', SupabaseConfig.anonKey);
      // Old-style anon keys are JWTs and are also sent as a bearer token.
      // New "publishable" keys are not JWTs and go in the apikey header only.
      if (SupabaseConfig.anonKey.startsWith('eyJ')) {
        req.headers.set('Authorization', 'Bearer ${SupabaseConfig.anonKey}');
      }
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return ApiResponse.failure(AuthStatus.server, _serverMessage(res.statusCode, text));
      }
      return ApiResponse.success(jsonDecode(text));
    } on TimeoutException {
      return const ApiResponse.failure(
          AuthStatus.network, 'The server took too long. Check your internet and try again.');
    } on SocketException {
      return const ApiResponse.failure(
          AuthStatus.network, 'No internet connection. Check your network and try again.');
    } on HandshakeException {
      return const ApiResponse.failure(
          AuthStatus.network, 'Secure connection failed. Check your internet and try again.');
    } catch (e) {
      return ApiResponse.failure(AuthStatus.server, 'Something went wrong. ($e)');
    } finally {
      client.close(force: true);
    }
  }

  static String _serverMessage(int code, String body) {
    if (code == 404 || body.contains('PGRST202') || body.contains('Could not find the function')) {
      return 'Database is not set up yet. Run supabase/setup.sql in the Supabase SQL Editor.';
    }
    if (code == 401 || code == 403) {
      return 'The Supabase key was rejected. Check lib/config/supabase_config.dart.';
    }
    return 'Server error ($code). Please try again.';
  }
}
