import 'package:flutter_test/flutter_test.dart';
import 'package:optional_mail_client/ui/mail/ics.dart';

String _ics(String body, {String method = 'REQUEST'}) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nMETHOD:$method\r\nBEGIN:VEVENT\r\n$body\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  test('reads a UTC meeting with escapes and folded lines', () {
    final i = parseInvite(
      _ics(
        'UID:abc-1\r\nSUMMARY:Planning\\, Q4\r\nDTSTART:20261105T140000Z\r\n'
        'DTEND:20261105T153000Z\r\nLOCATION:Room 4\\; 2nd floor\r\n'
        'DESCRIPTION:Line one\\nLine two\r\n'
        'ORGANIZER;CN="Ana Ray":mailto:ana@x.io\r\n'
        'X-FOLDED:aaa\r\n bbb',
      ),
    )!;
    expect(i.summary, 'Planning, Q4');
    expect(i.start, DateTime.utc(2026, 11, 5, 14));
    expect(i.end, DateTime.utc(2026, 11, 5, 15, 30));
    expect(i.allDay, isFalse);
    expect(i.location, 'Room 4; 2nd floor');
    expect(i.description, 'Line one\nLine two');
    expect(i.organizer, 'Ana Ray');
    expect(i.method, 'REQUEST');
    expect(i.uid, 'abc-1');
    expect(i.timeZone, isEmpty);
    expect(i.isCancellation, isFalse);
  });

  test('all-day dates keep an exclusive end', () {
    final i = parseInvite(
      _ics(
        'SUMMARY:Offsite\r\nDTSTART;VALUE=DATE:20261105\r\nDTEND;VALUE=DATE:20261107',
      ),
    )!;
    expect(i.allDay, isTrue);
    expect(i.start, DateTime.utc(2026, 11, 5));
    expect(i.end, DateTime.utc(2026, 11, 7));
  });

  test('missing end falls back to DURATION, then to one hour or day', () {
    final d = parseInvite(
      _ics('SUMMARY:A\r\nDTSTART:20261105T100000Z\r\nDURATION:PT45M'),
    )!;
    expect(d.end, DateTime.utc(2026, 11, 5, 10, 45));
    final h = parseInvite(_ics('SUMMARY:B\r\nDTSTART:20261105T100000Z'))!;
    expect(h.end, DateTime.utc(2026, 11, 5, 11));
    final day = parseInvite(_ics('SUMMARY:C\r\nDTSTART;VALUE=DATE:20261105'))!;
    expect(day.end, DateTime.utc(2026, 11, 6));
    final weird = parseInvite(
      _ics('SUMMARY:D\r\nDTSTART:20261105T100000Z\r\nDTEND:20261105T090000Z'),
    )!;
    expect(weird.end, DateTime.utc(2026, 11, 5, 11));
  });

  test('a named time zone is flagged because the client cannot convert it', () {
    final i = parseInvite(
      _ics(
        'SUMMARY:Z\r\nDTSTART;TZID=Asia/Kolkata:20261105T100000\r\nDTEND;TZID=Asia/Kolkata:20261105T110000',
      ),
    )!;
    expect(i.timeZone, 'Asia/Kolkata');
    expect(i.allDay, isFalse);
  });

  test('cancellations are recognised', () {
    final i = parseInvite(
      _ics('SUMMARY:Gone\r\nDTSTART:20261105T100000Z', method: 'CANCEL'),
    )!;
    expect(i.isCancellation, isTrue);
  });

  test('garbage and incomplete files give null, never throw', () {
    expect(parseInvite(''), isNull);
    expect(parseInvite('hello'), isNull);
    expect(parseInvite('BEGIN:VCALENDAR\r\nEND:VCALENDAR'), isNull);
    expect(parseInvite(_ics('SUMMARY:No start')), isNull);
    expect(parseInvite(_ics('SUMMARY:Bad\r\nDTSTART:soon')), isNull);
    expect(parseInvite('BEGIN:VEVENT\r\nDTSTART:20261105T100000Z'), isNull);
  });

  test('only the first event is read', () {
    final i = parseInvite(
      'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:One\r\nDTSTART:20261105T100000Z\r\nEND:VEVENT\r\n'
      'BEGIN:VEVENT\r\nSUMMARY:Two\r\nDTSTART:20261106T100000Z\r\nEND:VEVENT\r\nEND:VCALENDAR',
    )!;
    expect(i.summary, 'One');
  });
}
