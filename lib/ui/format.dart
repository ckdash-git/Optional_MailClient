import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:intl/intl.dart';
import 'package:optional_mail_client/api/client.dart';

/// Short date for message lists: time today, weekday this week, otherwise
/// the date.
String formatListDate(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final today = _day(now ?? DateTime.now());
  final day = _day(local);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat.jm().format(local);
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.E().format(local);
  if (local.year == today.year) return DateFormat.MMMd().format(local);
  return DateFormat.yMMMd().format(local);
}

/// Full date and time, e.g. for message headers.
String formatFullDate(DateTime date) =>
    DateFormat.yMMMEd().add_jm().format(date.toLocal());

String formatDayHeader(DateTime day, {DateTime? now}) {
  final today = _day(now ?? DateTime.now());
  final d = _day(day);
  final diff = d.difference(today).inDays;
  final label = DateFormat.MMMMEEEEd().format(d);
  if (diff == 0) return 'Today · $label';
  if (diff == 1) return 'Tomorrow · $label';
  if (diff == -1) return 'Yesterday · $label';
  return d.year == today.year ? label : DateFormat.yMMMMEEEEd().format(d);
}

String formatTime(DateTime t) => DateFormat.jm().format(t.toLocal());

String formatDate(DateTime t) => DateFormat.yMMMEd().format(t);

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// User-facing text for any error.
String describeError(Object? error) {
  if (error is ApiException) return error.userMessage;
  if (error is FormatException) return error.message;
  return 'Something went wrong. Please try again.';
}

final _emailPattern = RegExp(
  r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
);

/// Basic syntactic check of an email address.
bool isValidEmail(String s) => s.length <= 254 && _emailPattern.hasMatch(s);

/// Parses `email`, `Name <email>` or `"Name" <email>`. Returns null if the
/// address is not valid.
Address? parseAddress(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final angle = RegExp(r'^(.*)<([^<>]+)>$').firstMatch(text);
  if (angle != null) {
    final email = angle.group(2)!.trim();
    var name = angle.group(1)!.trim();
    if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
      name = name.substring(1, name.length - 1);
    }
    return isValidEmail(email) ? Address(name: name, email: email) : null;
  }
  return isValidEmail(text) ? Address(email: text) : null;
}

/// Up to two initials for an avatar.
String initialsOf(String name) {
  final words = name
      .replaceAll(RegExp(r'[<>"@].*$'), '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    final t = name.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }
  final first = words.first.characters.first;
  final last = words.length > 1 ? words.last.characters.first : '';
  return (first + last).toUpperCase();
}

/// Crude HTML to text conversion for quoting HTML-only messages in replies.
String htmlToText(String html) {
  var s = html
      .replaceAll(
        RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</(p|div|li|tr|h[1-6])>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
