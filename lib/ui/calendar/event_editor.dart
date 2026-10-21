import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';

enum _ConflictChoice { reload, overwrite, saveAsNew, cancel }

/// Create or edit an event. Pops `true` when something was saved or deleted.
class EventEditorScreen extends StatefulWidget {
  const EventEditorScreen({
    required this.account,
    required this.calendars,
    required this.calendarId,
    super.key,
    this.event,
    this.initialDay,
  });

  final Account account;
  final List<CalendarInfo> calendars;
  final String calendarId;
  final CalendarEvent? event;
  final DateTime? initialDay;

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();

  late String _calendarId = widget.calendarId;
  CalendarEvent? _event; // the server version being edited
  bool _allDay = false;
  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _saving = false;
  String? _rangeError;

  bool get _isNew => _event == null;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    if (event != null) {
      _fill(event);
    } else {
      final now = DateTime.now();
      final day = widget.initialDay ?? now;
      final isToday =
          day.year == now.year && day.month == now.month && day.day == now.day;
      final hour = isToday ? (now.hour + 1).clamp(0, 23) : 9;
      _startDate = DateTime(day.year, day.month, day.day);
      _endDate = _startDate;
      _startTime = TimeOfDay(hour: hour, minute: 0);
      _endTime = TimeOfDay(
        hour: (hour + 1).clamp(0, 23),
        minute: hour == 23 ? 59 : 0,
      );
    }
  }

  void _fill(CalendarEvent e) {
    _event = e;
    _calendarId = e.calendar.isEmpty ? widget.calendarId : e.calendar;
    _title.text = e.summary;
    _location.text = e.location;
    _description.text = e.description;
    _allDay = e.allDay;
    if (e.allDay) {
      // All-day dates are calendar dates; the end is exclusive.
      _startDate = DateTime(e.start.year, e.start.month, e.start.day);
      final end = DateTime(e.end.year, e.end.month, e.end.day - 1);
      _endDate = end.isBefore(_startDate) ? _startDate : end;
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
    } else {
      final s = e.start.toLocal();
      final en = e.end.toLocal();
      _startDate = DateTime(s.year, s.month, s.day);
      _endDate = DateTime(en.year, en.month, en.day);
      _startTime = TimeOfDay.fromDateTime(s);
      _endTime = TimeOfDay.fromDateTime(en);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime d, TimeOfDay t) =>
      DateTime(d.year, d.month, d.day, t.hour, t.minute);

  DateTime get _start => _combine(_startDate, _startTime);
  DateTime get _end => _combine(_endDate, _endTime);

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    // Whole days (UTC arithmetic avoids daylight-saving surprises).
    final days = DateTime.utc(picked.year, picked.month, picked.day)
        .difference(
          DateTime.utc(_startDate.year, _startDate.month, _startDate.day),
        )
        .inDays;
    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      _endDate = DateTime(_endDate.year, _endDate.month, _endDate.day + days);
      _rangeError = null;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _endDate = picked;
      _rangeError = null;
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked == null || !mounted) return;
    final duration = _end.difference(_start);
    setState(() {
      _startTime = picked;
      final end = _start.add(
        duration.isNegative ? const Duration(hours: 1) : duration,
      );
      _endDate = DateTime(end.year, end.month, end.day);
      _endTime = TimeOfDay.fromDateTime(end);
      _rangeError = null;
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _endTime = picked;
      _rangeError = null;
    });
  }

  EventInput? _input() {
    final DateTime start;
    final DateTime end;
    if (_allDay) {
      if (_endDate.isBefore(_startDate)) {
        setState(() => _rangeError = 'The end date is before the start date');
        return null;
      }
      start = DateTime.utc(_startDate.year, _startDate.month, _startDate.day);
      end = DateTime.utc(_endDate.year, _endDate.month, _endDate.day + 1);
    } else {
      if (!_end.isAfter(_start)) {
        setState(() => _rangeError = 'The event must end after it starts');
        return null;
      }
      start = _start.toUtc();
      end = _end.toUtc();
    }
    return EventInput(
      calendar: _calendarId,
      id: _event?.id,
      etag: _event?.etag,
      summary: _title.text.trim(),
      description: _description.text.trim(),
      location: _location.text.trim(),
      start: start,
      end: end,
      allDay: _allDay,
    );
  }

  Future<void> _save({bool asNew = false}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    var input = _input();
    if (input == null) return;
    if (asNew) {
      input = EventInput(
        calendar: input.calendar,
        summary: input.summary,
        description: input.description,
        location: input.location,
        start: input.start,
        end: input.end,
        allDay: input.allDay,
      );
    }
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await api.saveEvent(widget.account.id, input);
      navigator.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.isConflict) {
        await _resolveConflict();
      } else {
        showError(context, e);
      }
    }
  }

  /// Finds the current server version of the event being edited.
  Future<CalendarEvent?> _fetchCurrent() async {
    final e = _event!;
    final api = AppScope.of(context).api;
    final from = e.start.subtract(const Duration(days: 1));
    var to = e.end.add(const Duration(days: 1));
    if (to.difference(from).inDays > 365) {
      to = from.add(const Duration(days: 365));
    }
    final events = await api.events(
      widget.account.id,
      calendar: e.calendar,
      from: from,
      to: to,
    );
    for (final x in events) {
      if (x.id == e.id) return x;
    }
    return null;
  }

  Future<void> _resolveConflict() async {
    CalendarEvent? current;
    try {
      current = await _fetchCurrent();
    } on Object catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final deleted = current == null;
    final choice = await showDialog<_ConflictChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deleted ? 'Event was deleted' : 'Event was changed'),
        content: Text(
          deleted
              ? 'This event was deleted on another device.'
              : 'This event was changed on another device. Load the latest '
                    'version (your changes are lost) or keep your version?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ConflictChoice.cancel),
            child: const Text('Cancel'),
          ),
          if (deleted)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _ConflictChoice.saveAsNew),
              child: const Text('Save as new'),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(context, _ConflictChoice.reload),
              child: const Text('Load latest'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _ConflictChoice.overwrite),
              child: const Text('Keep mine'),
            ),
          ],
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _ConflictChoice.reload:
        setState(() => _fill(current!));
        showSnack(context, 'Loaded the latest version');
      case _ConflictChoice.overwrite:
        _event = current;
        await _save();
      case _ConflictChoice.saveAsNew:
        await _save(asNew: true);
      case _ConflictChoice.cancel || null:
        break;
    }
  }

  Future<void> _delete() async {
    final e = _event;
    if (e == null) return;
    final ok = await confirm(
      context,
      title: 'Delete event?',
      message: e.recurrence.isEmpty
          ? null
          : 'This is a repeating event. All occurrences are deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await api.deleteEvent(widget.account.id, id: e.id, etag: e.etag);
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Event deleted')));
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (err.isConflict || err.isNotFound) {
        navigator.pop(true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'The event was changed on another device. The calendar has '
              'been reloaded; please check it and try again.',
            ),
          ),
        );
      } else {
        showError(context, err);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = _event;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New event' : 'Edit event'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete event',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (e != null && e.recurrence.isNotEmpty)
                Card.filled(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: const Icon(Icons.repeat),
                    title: const Text('Repeating event'),
                    subtitle: Text(
                      'Changes apply to every occurrence. The repeat rule '
                      '(${e.recurrence}) cannot be edited in this app.',
                    ),
                  ),
                ),
              if (widget.calendars.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _calendarId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Calendar',
                    border: const OutlineInputBorder(),
                    helperText: _isNew
                        ? null
                        : 'Events cannot be moved between calendars',
                  ),
                  items: [
                    for (final c in widget.calendars)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name.isEmpty ? c.id : c.name),
                      ),
                  ],
                  onChanged: _isNew
                      ? (v) => setState(() => _calendarId = v!)
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _title,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Add a title' : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('All day'),
                value: _allDay,
                onChanged: (v) => setState(() {
                  _allDay = v;
                  _rangeError = null;
                }),
              ),
              _DateTimeRow(
                label: 'Starts',
                date: _startDate,
                time: _allDay ? null : _startTime,
                onPickDate: _pickStartDate,
                onPickTime: _pickStartTime,
              ),
              _DateTimeRow(
                label: 'Ends',
                date: _endDate,
                time: _allDay ? null : _endTime,
                onPickDate: _pickEndDate,
                onPickTime: _pickEndTime,
              ),
              if (_rangeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _rangeError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  prefixIcon: Icon(Icons.place_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
  });

  final String label;
  final DateTime date;
  final TimeOfDay? time;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final t = time;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.event_outlined),
            label: Text(
              formatDate(date),
              semanticsLabel: '$label date ${formatDate(date)}',
            ),
          ),
          if (t != null)
            OutlinedButton.icon(
              onPressed: onPickTime,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                t.format(context),
                semanticsLabel: '$label time ${t.format(context)}',
              ),
            ),
        ],
      ),
    );
  }
}
