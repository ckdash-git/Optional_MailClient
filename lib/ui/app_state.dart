import 'package:flutter/foundation.dart';
import 'package:optional_mail_client/api/client.dart';

enum HomeTab { mail, calendar, contacts, settings }

/// State shared by the home screens of one signed-in session.
class AppState extends ChangeNotifier {
  AppState(this._api);

  final ApiClient _api;

  List<Account> _accounts = const [];
  bool _loading = false;
  Object? _error;
  String? _deviceId;
  String? _selectedId;
  String _folder = 'INBOX';
  HomeTab _tab = HomeTab.mail;
  bool _disposed = false;
  int _gen = 0;

  List<Account> get accounts => _accounts;
  bool get loading => _loading;
  Object? get error => _error;
  String? get deviceId => _deviceId;
  String get folder => _folder;
  HomeTab get tab => _tab;

  Account? get selectedAccount {
    for (final a in _accounts) {
      if (a.id == _selectedId) return a;
    }
    return _accounts.isEmpty ? null : _accounts.first;
  }

  Account? accountById(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Loads `/v1/me`. Keeps the current selection when it still exists.
  Future<void> loadAccounts() async {
    final gen = ++_gen;
    _loading = true;
    _error = null;
    _notify();
    try {
      final me = await _api.me();
      if (gen != _gen) return; // a newer load is in flight
      _accounts = me.accounts;
      _deviceId = me.deviceId;
      if (accountById(_selectedId ?? '') == null) {
        _selectedId = _accounts.isEmpty ? null : _accounts.first.id;
        _folder = 'INBOX';
      }
      _loading = false;
    } on Object catch (e) {
      if (gen != _gen) return;
      _error = e;
      _loading = false;
    }
    _notify();
  }

  void selectAccount(String id) {
    if (id == selectedAccount?.id) return;
    _selectedId = id;
    _folder = 'INBOX';
    _notify();
  }

  void selectFolder(String folder) {
    if (folder == _folder) return;
    _folder = folder;
    _notify();
  }

  void selectTab(HomeTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    _notify();
  }

  /// Opens a mailbox, e.g. after a push notification was tapped.
  void openMailbox(String accountId, {String folder = 'INBOX'}) {
    // Kept even before accounts load; loadAccounts() keeps a valid selection.
    _selectedId = accountId;
    _folder = folder;
    _tab = HomeTab.mail;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
