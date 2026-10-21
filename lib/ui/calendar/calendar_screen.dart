import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/calendar/event_editor.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/account_menu.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';
import 'package:table_calendar/table_calendar.dart';

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// Local calendar days an event covers (all-day dates are taken as-is).
List<DateTime> eventDays(CalendarEvent e) {
  final DateTime first;
  final DateTime last;
  if (e.allDay) {
    first = DateTime(e.start.year, e.start.month, e.start.day);
    final endExclusive = DateTime(e.end.year, e.end.month, e.end.day);
    final l = DateTime(
      endExclusive.year,
      endExclusive.month,
      endExclusive.day - 1,
    );
    last = l.isBefore(first) ? first : l;
  } else {
    final s = e.start.toLocal();
    final en = e.end.toLocal();
    first = dateOnly(s);
    last = dateOnly(
      en.isAfter(s) ? en.subtract(const Duration(microseconds: 1)) : s,
    );
  }
  final days = <DateTime>[];
  for (
    var d = first;
    !d.isAfter(last) && days.length < 62;
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    days.add(d);
  }
  return days;
}

Color? parseCssColor(String css) {
  var s = css.trim();
  if (!s.startsWith('#')) return null;
  s = s.substring(1);
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length == 8) s = s.substring(6) + s.substring(0, 6); // RRGGBBAA
  if (s.length == 6) s = 'FF$s';
  final v = int.tryParse(s, radix: 16);
  return (v == null || s.length != 8) ? null : Color(v);
}

String eventTimeLabel(CalendarEvent e) {
  if (e.allDay) {
    final days = eventDays(e);
    return days.length > 1
        ? 'All day · ${DateFormat.MMMd().format(days.first)} – '
              '${DateFormat.MMMd().format(days.last)}'
        : 'All day';
  }
  final s = e.start.toLocal();
  final en = e.end.toLocal();
  if (dateOnly(s) == dateOnly(en)) {
    return '${formatTime(s)} – ${formatTime(en)}';
  }
  final f = DateFormat.MMMd().add_jm();
  return '${f.format(s)} – ${f.format(en)}';
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;
  final _scroll = ScrollController();

  Account? _account;
  List<CalendarInfo>? _calendars;
  Object? _calendarsError;
  String? _calendarId;

  DateTime _focused = dateOnly(DateTime.now());
  DateTime _selected = dateOnly(DateTime.now());
  CalendarFormat _format = CalendarFormat.month;

  List<CalendarEvent> _events = const [];
  Map<DateTime, List<CalendarEvent>> _byDay = const {};
  final Map<DateTime, GlobalKey> _dayKeys = {};
  DateTime? _loadedMonth;
  bool _loadingEvents = false;
  Object? _eventsError;
  int _gen = 0;

  ApiClient get _api => AppScope.of(context).api;

  CalendarInfo? get _calendar {
    for (final c in _calendars ?? const <CalendarInfo>[]) {
      if (c.id == _calendarId) return c;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= SessionScope.realtimeOf(context).events.listen(_onEvent);
    final account = SessionScope.watch(context).selectedAccount;
    if (account?.id != _account?.id) {
      _account = account;
      _calendars = null;
      _calendarsError = null;
      _calendarId = null;
      _setEvents(const []);
      _loadedMonth = null;
      if (account != null && account.hasCalendar) unawaited(_loadCalendars());
    } else {
      _account = account;
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onEvent(RealtimeEvent e) {
    if (e.isResync ||
        (e.type == 'calendar.changed' && e.accountId == _account?.id)) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (_calendars == null) {
          unawaited(_loadCalendars());
        } else {
          unawaited(_loadEvents(silent: true));
        }
      });
    }
  }

  Future<void> _loadCalendars() async {
    final account = _account;
    if (account == null) return;
    final gen = ++_gen;
    try {
      final list = await _api.calendars(account.id);
      if (!mounted || gen != _gen) return;
      setState(() {
        _calendars = list;
        if (!list.any((c) => c.id == _calendarId)) {
          _calendarId = list.isEmpty ? null : list.first.id;
        }
      });
      await _loadEvents();
    } on Object catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _calendarsError = e);
    }
  }

  void _setEvents(List<CalendarEvent> events) {
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final e in events) {
      for (final d in eventDays(e)) {
        (byDay[d] ??= []).add(e);
      }
    }
    for (final list in byDay.values) {
      list.sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.start.compareTo(b.start);
      });
    }
    _events = events;
    _byDay = byDay;
    _dayKeys.clear();
  }

  Future<void> _loadEvents({bool silent = false}) async {
    final account = _account;
    final calendarId = _calendarId;
    if (account == null || calendarId == null) return;
    final month = DateTime(_focused.year, _focused.month);
    final from = DateTime(month.year, month.month, 1 - 7);
    final to = DateTime(month.year, month.month + 1, 1 + 7);
    final gen = ++_gen;
    setState(() {
      _loadingEvents = true;
      if (!silent) _eventsError = null;
    });
    try {
      final events = await _api.events(
        account.id,
        calendar: calendarId,
        from: from,
        to: to,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _setEvents(events);
        _loadedMonth = month;
        _eventsError = null;
        _loadingEvents = false;
      });
    } on Object catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loadingEvents = false;
        if (!silent || _events.isEmpty) _eventsError = e;
      });
    }
  }

  void _onPageChanged(DateTime focused) {
    _focused = dateOnly(focused);
    final month = DateTime(_focused.year, _focused.month);
    if (month != _loadedMonth) {
      unawaited(_loadEvents());
    } else {
      setState(() {});
    }
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    final day = dateOnly(selected);
    final monthChanged =
        day.month != _focused.month || day.year != _focused.year;
    setState(() {
      _selected = day;
      _focused = dateOnly(focused);
    });
    if (monthChanged) {
      unawaited(_loadEvents());
      return;
    }
    final key = _dayKeys[day];
    if (key?.currentContext != null) {
      unawaited(
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          alignment: 0.05,
        ),
      );
    }
  }

  void _goToday() => _onDaySelected(DateTime.now(), DateTime.now());

  Future<void> _openEditor({CalendarEvent? event}) async {
    final account = _account;
    final calendars = _calendars;
    final calendarId = event?.calendar ?? _calendarId;
    if (account == null || calendars == null || calendarId == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: event == null,
        builder: (_) => EventEditorScreen(
          account: account,
          calendars: calendars,
          calendarId: calendarId,
          event: event,
          initialDay: _selected,
        ),
      ),
    );
    if (changed ?? false) await _loadEvents(silent: true);
  }

  StartingDayOfWeek _firstWeekday(BuildContext context) {
    final i = MaterialLocalizations.of(context).firstDayOfWeekIndex; // 0 = Sun
    return i == 0
        ? StartingDayOfWeek.sunday
        : StartingDayOfWeek.values[(i - 1) % 7];
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final calendars = _calendars;
    final actions = <Widget>[
      IconButton(
        tooltip: 'Today',
        onPressed: calendars == null ? null : _goToday,
        icon: const Icon(Icons.today_outlined),
      ),
      if (calendars != null && calendars.length > 1)
        PopupMenuButton<String>(
          tooltip: 'Choose calendar',
          icon: const Icon(Icons.event_note_outlined),
          onSelected: (id) {
            setState(() => _calendarId = id);
            unawaited(_loadEvents());
          },
          itemBuilder: (context) => [
            for (final c in calendars)
              CheckedPopupMenuItem(
                value: c.id,
                checked: c.id == _calendarId,
                child: Text(c.name.isEmpty ? c.id : c.name),
              ),
          ],
        ),
      const AccountMenuButton(),
    ];
    final ios = isIOS(context);
    return Scaffold(
      appBar: ios
          ? null
          : AppBar(
              title: AppBarTitle(
                'Calendar',
                subtitle: _calendar?.name ?? account?.email,
              ),
              actions: actions,
            ),
      floatingActionButton: _calendarId == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'new-event',
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: const Text('Event'),
            ),
      body: ios
          ? NestedScrollView(
              headerSliverBuilder: (context, _) => [
                largeTitleBar(
                  context,
                  'Calendar',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  ),
                ),
              ],
              body: _body(account, calendars),
            )
          : _body(account, calendars),
    );
  }

  Widget _body(Account? account, List<CalendarInfo>? calendars) {
    if (account == null) return const LoadingView();
    if (!account.hasCalendar) {
      return MessageView(
        icon: Icons.event_busy_outlined,
        title: 'No calendar',
        message:
            'There is no calendar (CalDAV) set up for ${account.email}. '
            'You can add a CalDAV address when adding the account.',
      );
    }
    if (calendars == null) {
      return _calendarsError != null
          ? ErrorView(
              error: _calendarsError,
              onRetry: () {
                setState(() => _calendarsError = null);
                unawaited(_loadCalendars());
              },
            )
          : const LoadingView(label: 'Loading calendars');
    }
    if (calendars.isEmpty) {
      return const MessageView(
        icon: Icons.event_busy_outlined,
        title: 'No calendars',
        message: 'This account has no calendars yet.',
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final color =
        parseCssColor(_calendar?.color ?? '') ??
        systemColor(_calendar?.id ?? 'calendar', theme.brightness);
    final monthDays =
        _byDay.keys
            .where((d) => d.year == _focused.year && d.month == _focused.month)
            .toList()
          ..sort();

    return RefreshIndicator(
      onRefresh: () => _loadEvents(silent: true),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: TableCalendar<CalendarEvent>(
              firstDay: DateTime.utc(2000),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focused,
              currentDay: DateTime.now(),
              calendarFormat: _format,
              availableCalendarFormats: const {
                CalendarFormat.month: 'Month',
                CalendarFormat.twoWeeks: '2 weeks',
                CalendarFormat.week: 'Week',
              },
              startingDayOfWeek: _firstWeekday(context),
              rowHeight: scaler.scale(48).clamp(48, 88),
              daysOfWeekHeight: scaler.scale(20).clamp(20, 40),
              selectedDayPredicate: (d) => isSameDay(d, _selected),
              eventLoader: (d) => _byDay[dateOnly(d)] ?? const [],
              onDaySelected: _onDaySelected,
              onPageChanged: _onPageChanged,
              onFormatChanged: (f) => setState(() => _format = f),
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonShowsNext: false,
                titleTextStyle: theme.textTheme.titleMedium!,
                formatButtonTextStyle: theme.textTheme.labelMedium!,
                formatButtonDecoration: BoxDecoration(
                  border: Border.all(color: scheme.outline),
                  borderRadius: BorderRadius.circular(16),
                ),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  semanticLabel: 'Previous',
                  color: scheme.onSurface,
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  semanticLabel: 'Next',
                  color: scheme.onSurface,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: theme.textTheme.labelSmall!,
                weekendStyle: theme.textTheme.labelSmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                defaultTextStyle: theme.textTheme.bodyMedium!,
                weekendTextStyle: theme.textTheme.bodyMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                todayDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.primary, width: 1.5),
                ),
                todayTextStyle: theme.textTheme.bodyMedium!.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
                selectedDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
                selectedTextStyle: theme.textTheme.bodyMedium!.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
                markerDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
                markersMaxCount: 3,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 4,
              child: _loadingEvents ? const LinearProgressIndicator() : null,
            ),
          ),
          if (_eventsError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      describeError(_eventsError),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loadEvents,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          else if (monthDays.isEmpty && !_loadingEvents)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No events in ${DateFormat.yMMMM().format(_focused)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SliverList.list(
              children: [
                for (final day in monthDays) ...[
                  _DayHeader(
                    key: _dayKeys.putIfAbsent(day, GlobalKey.new),
                    day: day,
                    selected: day == _selected,
                  ),
                  for (final e in _byDay[day]!)
                    _EventTile(
                      event: e,
                      color: color,
                      onTap: () => _openEditor(event: e),
                    ),
                ],
                const SizedBox(height: 88),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.selected, super.key});

  final DateTime day;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          formatDayHeader(day),
          style: theme.textTheme.titleSmall?.copyWith(
            color: selected ? theme.colorScheme.primary : null,
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.color,
    required this.onTap,
  });

  final CalendarEvent event;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final theme = Theme.of(context);
    final start = e.allDay ? 'All day' : formatTime(e.start);
    return Semantics(
      container: true,
      button: true,
      label: [
        e.summary,
        eventTimeLabel(e),
        if (e.location.isNotEmpty) e.location,
      ].join('. '),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Timetable column: departure time bold, arrival muted, figures aligned.
                SizedBox(
                  width: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        start,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (!e.allDay)
                        Text(
                          formatTime(e.end),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                ExcludeSemantics(
                  child: Container(
                    width: 3,
                    margin: const EdgeInsets.only(right: 12),
                    color: color,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        e.summary.isEmpty ? '(no title)' : e.summary,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (e.location.isNotEmpty)
                        Text(
                          e.location,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (e.recurrence.isNotEmpty)
                  const Icon(Icons.repeat, size: 18, semanticLabel: 'Repeats'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
