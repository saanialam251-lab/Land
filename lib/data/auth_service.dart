import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_api.dart';

export 'supabase_api.dart' show AuthStatus;

class AuthResult {
  final AuthStatus status;
  final AuthUser? user;
  final String message;
  const AuthResult(this.status, {this.user, this.message = ''});
  bool get ok => status == AuthStatus.ok;
}

class AuthUser {
  final String id;
  final String name;
  final String phone;
  final String email;

  /// Secret session code from the database; proves who is logged in on this phone.
  final String token;
  const AuthUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    this.token = '',
  });

  /// First word of the name with a capital first letter ("sUNNY alam" -> "Sunny").
  String get firstName => AuthService.prettyFirstName(name);

  /// One or two capital letters for the avatar.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'email': email, 'token': token};

  static AuthUser? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id']?.toString();
    final name = j['name']?.toString();
    if (id == null || id.isEmpty || name == null || name.trim().isEmpty) return null;
    return AuthUser(
      id: id,
      name: name,
      phone: j['phone']?.toString() ?? '',
      email: j['email']?.toString() ?? '',
      token: j['token']?.toString() ?? '',
    );
  }
}

/// Sign up / log in against Supabase (two SQL functions, see supabase/setup.sql)
/// and remember who is logged in on this phone.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService I = AuthService._();

  static const _prefsKey = 'auth_user';

  AuthUser? user;
  bool get loggedIn => user != null;

  // ── Rules (the same rules are enforced again by the SQL functions) ────

  /// Only the FIRST word counts, capitals do not matter:
  /// "Sunny Alam Chaudhary" -> "sunny", "SUNNY" -> "sunny".
  static String firstNameOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.first.toLowerCase();
  }

  static String prettyFirstName(String name) {
    final f = name.trim().split(RegExp(r'\s+')).first;
    if (f.isEmpty) return '';
    return f.substring(0, 1).toUpperCase() + f.substring(1).toLowerCase();
  }

  static String digitsOf(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  static String? validateName(String name) =>
      firstNameOf(name).length < 2 ? 'Please enter your name (at least 2 letters).' : null;

  static String? validatePhone(String phone) {
    final n = digitsOf(phone).length;
    return (n < 7 || n > 15) ? 'Enter a valid phone number.' : null;
  }

  static String? validateEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim()) ? null : 'Enter a valid email address.';

  // ── Session ──────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      final u = raw == null ? null : AuthUser.fromJson(jsonDecode(raw));
      user = (u == null || u.token.isEmpty) ? null : u;
    } catch (_) {
      user = null;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    final token = user?.token ?? '';
    if (token.isNotEmpty) {
      // best effort: the phone is logged out even if this call fails
      await SupabaseApi.rpc('logout_user', {'p_token': token});
    }
    await expireSession();
  }

  /// Forget the login on this phone (also used when the database says the session is gone).
  Future<void> expireSession() async {
    user = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefsKey);
    } catch (_) {}
    notifyListeners();
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<AuthResult> login(String name, String phone) {
    return _call('login_user', {'p_name': name.trim(), 'p_phone': phone.trim()}, (m) async {
      if (m['ok'] == true) {
        final u = AuthUser.fromJson(m['user']);
        if (u == null) {
          return const AuthResult(AuthStatus.server, message: 'Unexpected reply from the server.');
        }
        user = u;
        try {
          final p = await SharedPreferences.getInstance();
          await p.setString(_prefsKey, jsonEncode(u.toJson()));
        } catch (_) {}
        notifyListeners();
        return AuthResult(AuthStatus.ok, user: u);
      }
      return const AuthResult(
        AuthStatus.wrongDetails,
        message: "We couldn't find an account with that name and phone number.",
      );
    });
  }

  Future<AuthResult> signUp(String name, String phone, String email) {
    return _call(
      'create_account',
      {'p_name': name.trim(), 'p_phone': phone.trim(), 'p_email': email.trim()},
      (m) async {
        if (m['ok'] == true) return const AuthResult(AuthStatus.ok);
        switch (m['error']) {
          case 'phone_exists':
            return const AuthResult(AuthStatus.phoneExists,
                message: 'That phone number already has an account. Please log in.');
          case 'email_exists':
            return const AuthResult(AuthStatus.emailExists,
                message: 'That email is already used. Please log in instead.');
          default:
            return const AuthResult(AuthStatus.server,
                message: 'Please check your name, phone number and email.');
        }
      },
    );
  }

  // ── Network ──────────────────────────────────────────────────────────

  Future<AuthResult> _call(
    String fn,
    Map<String, dynamic> body,
    Future<AuthResult> Function(Map<String, dynamic>) handle,
  ) async {
    final r = await SupabaseApi.rpc(fn, body);
    if (!r.ok) return AuthResult(r.status, message: r.message);
    final decoded = r.json;
    if (decoded is! Map) {
      return const AuthResult(AuthStatus.server, message: 'Unexpected reply from the server.');
    }
    return handle(Map<String, dynamic>.from(decoded));
  }
}
