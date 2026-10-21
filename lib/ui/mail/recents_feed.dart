import 'package:optional_mail_client/api/client.dart';

/// A recent message together with the account it belongs to.
typedef Recent = ({Account account, MessageSummary message});

typedef FetchInbox = Future<MessagePage> Function(
  Account account,
  String? before,
  int limit,
);

/// Newest-first messages across accounts, loaded a page at a time.
///
/// Each account's inbox is already newest-first, so this is a k-way merge. A
/// message is only shown once no account can still hold a newer one: the
/// shown list ([items]) stops at the oldest message fetched from any account
/// that has more pages. Extending fetches from that limiting account first.
class RecentsFeed {
  RecentsFeed(this._fetch, List<Account> accounts, {this.pageSize = 20})
    : _sources = [for (final a in accounts) _Source(a)];

  final FetchInbox _fetch;
  final int pageSize;
  final List<_Source> _sources;

  /// Safety valve: one [extend] never makes more requests than this.
  static const _maxRequests = 60;

  /// The merged messages that are safe to show, newest first.
  List<Recent> get items {
    final all = <Recent>[
      for (final s in _sources)
        for (final m in s.messages) (account: s.account, message: m),
    ]..sort((a, b) => b.message.date.compareTo(a.message.date));
    final floor = _floor;
    return floor == null
        ? all
        : all.where((r) => !r.message.date.isBefore(floor)).toList();
  }

  /// Whether more messages can be fetched.
  bool get hasMore => _sources.any((s) => !s.done);

  /// The date below which an unfetched message may still hide, or null when
  /// every account has been read to the end.
  DateTime? get _floor {
    DateTime? floor;
    for (final s in _sources) {
      if (s.done) continue;
      // An account not asked yet could hold anything.
      if (!s.started) return DateTime.utc(9999);
      final oldest = s.messages.last.date;
      if (floor == null || oldest.isAfter(floor)) floor = oldest;
    }
    return floor;
  }

  /// Fetches until [want] messages can be shown or nothing is left.
  Future<void> extend(int want) async {
    for (var requests = 0; requests < _maxRequests; requests++) {
      if (items.length >= want) return;
      final next = _limiting();
      if (next == null) return;
      final page = await _fetch(next.account, next.next, pageSize);
      next.started = true;
      next.messages.addAll(page.messages);
      next.next = page.nextBefore;
      // An empty page can't move the cursor: treat the account as read.
      if (page.messages.isEmpty) next.next = null;
    }
  }

  /// The account to read next: one not started yet, else the one whose oldest
  /// fetched message is newest (it holds back the shown list the most).
  _Source? _limiting() {
    _Source? best;
    for (final s in _sources) {
      if (s.done) continue;
      if (!s.started) return s;
      if (best == null ||
          s.messages.last.date.isAfter(best.messages.last.date)) {
        best = s;
      }
    }
    return best;
  }
}

class _Source {
  _Source(this.account);

  final Account account;
  final List<MessageSummary> messages = [];
  String? next;
  bool started = false;

  bool get done => started && next == null;
}
