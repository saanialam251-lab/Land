import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'supabase_api.dart';

class SavedMeasurement {
  final String id;
  final String mode; // distance / room / height
  final double meters;
  final double? sqMeters;
  final int points;
  final DateTime at;

  SavedMeasurement({
    required this.id,
    required this.mode,
    required this.meters,
    this.sqMeters,
    required this.points,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode,
        'm': meters,
        'a': sqMeters,
        'p': points,
        't': at.millisecondsSinceEpoch,
      };

  factory SavedMeasurement.fromJson(Map<String, dynamic> j) => SavedMeasurement(
        id: j['id'] as String,
        mode: j['mode'] as String,
        meters: (j['m'] as num).toDouble(),
        sqMeters: (j['a'] as num?)?.toDouble(),
        points: (j['p'] as num?)?.toInt() ?? 2,
        at: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
      );
}

enum SyncState { guest, idle, syncing, offline, error }

/// Saved measurements, newest first.
///
/// Logged out: kept on this phone only ("guest" history).
/// Logged in:  every account has its own history stored in the Supabase database,
///             so it survives uninstalling the app and follows the account to any phone.
///             New saves / deletes made offline are remembered and sent later.
class HistoryStore extends ChangeNotifier {
  HistoryStore._();
  static final HistoryStore I = HistoryStore._();

  final List<SavedMeasurement> items = [];
  final Set<String> _pendingUp = {}; // saved here, not yet in the database
  final Set<String> _pendingDel = {}; // deleted here, not yet deleted in the database

  String? _ownerId; // null = guest
  bool _syncing = false;
  bool _again = false;
  bool _listening = false;

  SyncState syncState = SyncState.guest;
  String syncMessage = '';
  DateTime? lastSynced;

  String get _itemsKey => _ownerId == null ? 'history' : 'history_$_ownerId';
  String get _upKey => 'history_up_$_ownerId';
  String get _delKey => 'history_del_$_ownerId';

  Future<void> load() async {
    if (!_listening) {
      _listening = true;
      AuthService.I.addListener(_onAuth);
    }
    await _switchOwner(AuthService.I.user?.id);
  }

  void _onAuth() {
    final id = AuthService.I.user?.id;
    if (id != _ownerId) unawaited(_switchOwner(id));
  }

  static List<SavedMeasurement> _parse(Iterable<String> raw) {
    final out = <SavedMeasurement>[];
    for (final s in raw) {
      try {
        out.add(SavedMeasurement.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _switchOwner(String? id) async {
    _ownerId = id;
    items.clear();
    _pendingUp.clear();
    _pendingDel.clear();
    syncState = id == null ? SyncState.guest : SyncState.idle;
    syncMessage = '';
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      if (_ownerId != id) return; // account changed while loading
      items.addAll(_parse(p.getStringList(_itemsKey) ?? const <String>[]));
      if (id != null) {
        _pendingUp.addAll(p.getStringList(_upKey) ?? const <String>[]);
        _pendingDel.addAll(p.getStringList(_delKey) ?? const <String>[]);
      }
    } catch (_) {}
    notifyListeners();
    if (id != null) unawaited(syncNow());
  }

  Future<void> _persist() async {
    final itemsKey = _itemsKey;
    final upKey = _upKey;
    final delKey = _delKey;
    final owned = _ownerId != null;
    final encoded = items.map((e) => jsonEncode(e.toJson())).toList();
    final up = _pendingUp.toList();
    final del = _pendingDel.toList();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(itemsKey, encoded);
      if (owned) {
        await p.setStringList(upKey, up);
        await p.setStringList(delKey, del);
      }
    } catch (_) {}
  }

  void add(SavedMeasurement m) {
    items.insert(0, m);
    if (_ownerId != null) {
      _pendingDel.remove(m.id);
      _pendingUp.add(m.id);
    }
    notifyListeners();
    _persist();
    if (_ownerId != null) unawaited(syncNow());
  }

  void remove(String id) {
    items.removeWhere((e) => e.id == id);
    if (_ownerId != null) {
      _pendingUp.remove(id);
      _pendingDel.add(id);
    }
    notifyListeners();
    _persist();
    if (_ownerId != null) unawaited(syncNow());
  }

  void clear() {
    if (_ownerId != null) {
      _pendingDel.addAll(items.map((e) => e.id));
      _pendingUp.clear();
    }
    items.clear();
    notifyListeners();
    _persist();
    if (_ownerId != null) unawaited(syncNow());
  }

  // ── Cloud sync ──────────────────────────────────────────────────────

  /// Sends pending changes, then downloads the account's full history.
  Future<void> syncNow() async {
    final owner = _ownerId;
    final token = AuthService.I.user?.token ?? '';
    if (owner == null || token.isEmpty) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    syncState = SyncState.syncing;
    syncMessage = '';
    notifyListeners();
    try {
      do {
        _again = false;
        final ok = await _syncOnce(owner, token);
        if (!ok) break;
      } while (_again && _ownerId == owner);
    } finally {
      _syncing = false;
    }
  }

  bool _accept(ApiResponse r) {
    if (!r.ok) {
      syncState = r.status == AuthStatus.network ? SyncState.offline : SyncState.error;
      syncMessage = r.message;
      notifyListeners();
      return false;
    }
    final j = r.json;
    if (j is Map && j['ok'] == false) {
      if (j['error'] == 'bad_session') {
        // the login is no longer valid -> back to guest mode
        unawaited(AuthService.I.expireSession());
        return false;
      }
      syncState = SyncState.error;
      syncMessage = 'Could not sync (${j['error']}).';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> _syncOnce(String owner, String token) async {
    // 1) deletions made here
    for (final id in _pendingDel.toList()) {
      final r = await SupabaseApi.rpc('delete_measurement', {'p_token': token, 'p_id': id});
      if (_ownerId != owner) return false;
      if (!_accept(r)) return false;
      _pendingDel.remove(id);
    }
    // 2) saves made here
    for (final id in _pendingUp.toList()) {
      final idx = items.indexWhere((e) => e.id == id);
      if (idx < 0) {
        _pendingUp.remove(id);
        continue;
      }
      final r = await SupabaseApi.rpc(
        'save_measurement',
        {'p_token': token, 'p_id': id, 'p_data': items[idx].toJson()},
      );
      if (_ownerId != owner) return false;
      if (!_accept(r)) return false;
      _pendingUp.remove(id);
    }
    // 3) everything the account has in the database
    final r = await SupabaseApi.rpc('list_measurements', {'p_token': token});
    if (_ownerId != owner) return false;
    if (!_accept(r)) return false;

    final merged = <String, SavedMeasurement>{};
    final json = r.json;
    if (json is Map && json['items'] is List) {
      for (final e in json['items'] as List) {
        try {
          final m = SavedMeasurement.fromJson(Map<String, dynamic>.from(e as Map));
          if (!_pendingDel.contains(m.id)) merged[m.id] = m;
        } catch (_) {}
      }
    }
    for (final m in items) {
      if (_pendingUp.contains(m.id)) merged[m.id] = m; // not uploaded yet: keep
    }
    items
      ..clear()
      ..addAll(merged.values);
    items.sort((a, b) => b.at.compareTo(a.at));
    lastSynced = DateTime.now();
    syncState = SyncState.idle;
    syncMessage = '';
    notifyListeners();
    await _persist();
    return true;
  }
}
