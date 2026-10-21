/// A meeting invitation read from an iCalendar (`text/calendar`) attachment.
class Invite {
  const Invite({
    required this.summary,
    required this.start,
    required this.end,
    required this.allDay,
    this.location = '',
    this.description = '',
    this.organizer = '',
    this.method = '',
    this.uid = '',
    this.timeZone = '',
  });

  final String summary;

  /// UTC. All-day events use midnight UTC dates with an exclusive [end].
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String location;
  final String description;
  final String organizer;

  /// iTIP method: REQUEST, CANCEL, PUBLISH, REPLY...
  final String method;
  final String uid;

  /// Set when the sender gave a local time in a named zone (`TZID=...`). The
  /// client has no zone database, so [start] and [end] then read the time on
  /// this device's clock and the card tells the user to check it.
  final String timeZone;

  bool get isCancellation => method.toUpperCase() == 'CANCEL';
}

/// Reads the first event of [ics], or null when there is none.
Invite? parseInvite(String ics) {
  // Unfold: a line starting with a space or tab continues the previous one.
  final lines = ics
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '')
      .split('\n');

  var method = '';
  var inEvent = false;
  var done = false;
  final props = <String, ({String value, Map<String, String> params})>{};
  for (final line in lines) {
    final upper = line.toUpperCase();
    if (upper == 'BEGIN:VEVENT') {
      if (done) break;
      inEvent = true;
      continue;
    }
    if (upper == 'END:VEVENT') {
      inEvent = false;
      done = true;
      continue;
    }
    final colon = _valueStart(line);
    if (colon < 0) continue;
    final head = line.substring(0, colon).split(';');
    final name = head.first.toUpperCase();
    final value = line.substring(colon + 1);
    if (!inEvent) {
      if (name == 'METHOD') method = value.trim();
      continue;
    }
    final params = <String, String>{};
    for (final p in head.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) {
        params[p.substring(0, eq).toUpperCase()] = p
            .substring(eq + 1)
            .replaceAll('"', '');
      }
    }
    props.putIfAbsent(name, () => (value: value, params: params));
  }
  if (!done) return null;

  final dtStart = props['DTSTART'];
  if (dtStart == null) return null;
  final start = _parseTime(dtStart.value, dtStart.params);
  if (start == null) return null;
  final dtEnd = props['DTEND'];
  var end = dtEnd == null ? null : _parseTime(dtEnd.value, dtEnd.params);
  end ??= _fromDuration(start.time, props['DURATION']?.value, start.allDay);
  if (!end.time.isAfter(start.time)) {
    end = (
      time: start.time.add(
        start.allDay ? const Duration(days: 1) : const Duration(hours: 1),
      ),
      allDay: start.allDay,
      zone: start.zone,
    );
  }

  final organizer = props['ORGANIZER'];
  return Invite(
    summary: _unescape(props['SUMMARY']?.value ?? ''),
    start: start.time,
    end: end.time,
    allDay: start.allDay,
    location: _unescape(props['LOCATION']?.value ?? ''),
    description: _unescape(props['DESCRIPTION']?.value ?? ''),
    organizer: organizer == null
        ? ''
        : (organizer.params['CN'] ??
              organizer.value.replaceFirst(
                RegExp('^mailto:', caseSensitive: false),
                '',
              )),
    method: method,
    uid: props['UID']?.value ?? '',
    timeZone: start.zone,
  );
}

/// Index of the colon that ends the name and parameters (not one inside quotes).
int _valueStart(String line) {
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') quoted = !quoted;
    if (c == ':' && !quoted) return i;
  }
  return -1;
}

typedef _Time = ({DateTime time, bool allDay, String zone});

_Time? _parseTime(String value, Map<String, String> params) {
  final v = value.trim();
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$')
      .firstMatch(v);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  final dateOnly = m.group(4) == null;
  if (dateOnly) {
    return (time: DateTime.utc(g(1), g(2), g(3)), allDay: true, zone: '');
  }
  if (m.group(7) != null) {
    return (
      time: DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)),
      allDay: false,
      zone: '',
    );
  }
  // Floating or TZID time: read it on this device's clock.
  return (
    time: DateTime(g(1), g(2), g(3), g(4), g(5), g(6)).toUtc(),
    allDay: false,
    zone: params['TZID'] ?? '',
  );
}

_Time _fromDuration(DateTime start, String? duration, bool allDay) {
  final m = RegExp(
    r'^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  ).firstMatch(duration?.trim() ?? '');
  Duration d;
  if (m == null) {
    d = allDay ? const Duration(days: 1) : const Duration(hours: 1);
  } else {
    int n(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    d = Duration(
      days: n(1) * 7 + n(2),
      hours: n(3),
      minutes: n(4),
      seconds: n(5),
    );
  }
  return (time: start.add(d), allDay: allDay, zone: '');
}

String _unescape(String s) => s
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\')
    .trim();
