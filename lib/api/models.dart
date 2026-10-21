// Typed wire models for the master API (docs/API.md).
//
// Parsing is hand written and tolerant of missing optional fields. Request
// bodies omit unset optional fields because the master rejects unknown or
// malformed JSON with `400 bad_request`.

typedef Json = Map<String, Object?>;

String _str(Json j, String key) => j[key] as String? ?? '';

String? _optStr(Json j, String key) {
  final v = j[key] as String?;
  return (v == null || v.isEmpty) ? null : v;
}

int _int(Json j, String key) => (j[key] as num?)?.toInt() ?? 0;

bool _bool(Json j, String key) => j[key] as bool? ?? false;

DateTime _time(Json j, String key) {
  final raw = j[key] as String?;
  return (raw == null ? null : DateTime.tryParse(raw))?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

List<T> _list<T>(Json j, String key, T Function(Json) parse) {
  final raw = j[key] as List<Object?>?;
  if (raw == null) return <T>[];
  return [for (final e in raw) parse(e! as Json)];
}

List<String> _strings(Json j, String key) {
  final raw = j[key] as List<Object?>?;
  return raw == null ? <String>[] : [for (final e in raw) e! as String];
}

/// Formats [t] as RFC 3339 in UTC without fractional seconds.
String rfc3339(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

// ---------------------------------------------------------------------------
// Server settings and accounts

enum IncomingProtocol {
  imap('imap', 'IMAP'),
  pop3('pop3', 'POP3');

  const IncomingProtocol(this.wire, this.label);
  final String wire;
  final String label;

  static IncomingProtocol parse(String s) =>
      s == 'pop3' ? IncomingProtocol.pop3 : IncomingProtocol.imap;
}

enum Security {
  tls('tls', 'SSL/TLS'),
  starttls('starttls', 'STARTTLS'),
  none('none', 'None');

  const Security(this.wire, this.label);
  final String wire;
  final String label;

  static Security parse(String s) => switch (s) {
    'starttls' => Security.starttls,
    'none' => Security.none,
    _ => Security.tls,
  };
}

class ServerEndpoint {
  const ServerEndpoint({
    required this.host,
    required this.port,
    required this.security,
    this.protocol,
  });

  factory ServerEndpoint.fromJson(Json j) => ServerEndpoint(
    protocol: j['protocol'] == null
        ? null
        : IncomingProtocol.parse(_str(j, 'protocol')),
    host: _str(j, 'host'),
    port: _int(j, 'port'),
    security: Security.parse(_str(j, 'security')),
  );

  /// Only set for the incoming endpoint.
  final IncomingProtocol? protocol;
  final String host;
  final int port;
  final Security security;

  Json toJson() => {
    if (protocol != null) 'protocol': protocol!.wire,
    'host': host,
    'port': port,
    'security': security.wire,
  };
}

class ServerSettings {
  const ServerSettings({
    required this.incoming,
    required this.outgoing,
    this.caldavUrl,
    this.carddavUrl,
  });

  factory ServerSettings.fromJson(Json j) => ServerSettings(
    incoming: ServerEndpoint.fromJson(j['incoming']! as Json),
    outgoing: ServerEndpoint.fromJson(j['outgoing']! as Json),
    caldavUrl: _optStr(j, 'caldav_url'),
    carddavUrl: _optStr(j, 'carddav_url'),
  );

  final ServerEndpoint incoming;
  final ServerEndpoint outgoing;
  final String? caldavUrl;
  final String? carddavUrl;

  Json toJson() => {
    'incoming': incoming.toJson(),
    'outgoing': outgoing.toJson(),
    if (caldavUrl != null && caldavUrl!.isNotEmpty) 'caldav_url': caldavUrl,
    if (carddavUrl != null && carddavUrl!.isNotEmpty) 'carddav_url': carddavUrl,
  };
}

class Account {
  const Account({
    required this.id,
    required this.email,
    this.displayName = '',
    this.incomingProtocol = IncomingProtocol.imap,
    this.hasCalendar = false,
    this.hasContacts = false,
    this.lastError = '',
  });

  factory Account.fromJson(Json j) => Account(
    id: _str(j, 'id'),
    email: _str(j, 'email'),
    displayName: _str(j, 'display_name'),
    incomingProtocol: IncomingProtocol.parse(_str(j, 'incoming_protocol')),
    hasCalendar: _bool(j, 'has_calendar'),
    hasContacts: _bool(j, 'has_contacts'),
    lastError: _str(j, 'last_error'),
  );

  final String id;
  final String email;
  final String displayName;
  final IncomingProtocol incomingProtocol;
  final bool hasCalendar;
  final bool hasContacts;
  final String lastError;

  bool get isImap => incomingProtocol == IncomingProtocol.imap;
  String get label => displayName.isEmpty ? email : displayName;
}

class Address {
  const Address({required this.email, this.name = ''});

  factory Address.fromJson(Json j) =>
      Address(name: _str(j, 'name'), email: _str(j, 'email'));

  final String name;
  final String email;

  /// Name if known, otherwise the email address.
  String get label => name.trim().isEmpty ? email : name.trim();

  /// `Name <email>` or just `email`.
  String get formatted =>
      name.trim().isEmpty ? email : '${name.trim()} <$email>';

  Json toJson() => {'name': name, 'email': email};

  @override
  bool operator ==(Object other) =>
      other is Address &&
      other.email.toLowerCase() == email.toLowerCase() &&
      other.name == name;

  @override
  int get hashCode => Object.hash(email.toLowerCase(), name);
}

// ---------------------------------------------------------------------------
// Auth and devices

class Tokens {
  const Tokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
  });

  factory Tokens.fromJson(Json j) => Tokens(
    accessToken: _str(j, 'access_token'),
    accessExpiresAt: _time(j, 'access_expires_at'),
    refreshToken: _str(j, 'refresh_token'),
  );

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;

  Json toJson() => {
    'access_token': accessToken,
    'access_expires_at': rfc3339(accessExpiresAt),
    'refresh_token': refreshToken,
  };
}

class User {
  const User({required this.id, required this.email});

  factory User.fromJson(Json j) =>
      User(id: _str(j, 'id'), email: _str(j, 'email'));

  final String id;
  final String email;
}

class LoginResult {
  const LoginResult({
    required this.tokens,
    required this.user,
    required this.accountId,
  });

  factory LoginResult.fromJson(Json j) => LoginResult(
    tokens: Tokens.fromJson(j),
    user: User.fromJson(j['user']! as Json),
    accountId: _str(j, 'account_id'),
  );

  final Tokens tokens;
  final User user;
  final String accountId;
}

class Me {
  const Me({
    required this.user,
    required this.deviceId,
    required this.accounts,
  });

  factory Me.fromJson(Json j) => Me(
    user: User.fromJson(j['user']! as Json),
    deviceId: _str(j, 'device_id'),
    accounts: _list(j, 'accounts', Account.fromJson),
  );

  final User user;
  final String deviceId;
  final List<Account> accounts;
}

class Device {
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
  });

  factory Device.fromJson(Json j) => Device(
    id: _str(j, 'id'),
    name: _str(j, 'name'),
    platform: _str(j, 'platform'),
    createdAt: _time(j, 'created_at'),
    lastSeenAt: _time(j, 'last_seen_at'),
    current: _bool(j, 'current'),
  );

  final String id;
  final String name;
  final String platform;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool current;
}

// ---------------------------------------------------------------------------
// Mail

enum FolderRole {
  inbox('inbox'),
  sent('sent'),
  drafts('drafts'),
  trash('trash'),
  junk('junk'),
  archive('archive'),
  none('');

  const FolderRole(this.wire);
  final String wire;

  static FolderRole parse(String s) =>
      FolderRole.values.firstWhere((r) => r.wire == s, orElse: () => none);
}

class Folder {
  const Folder({
    required this.name,
    this.role = FolderRole.none,
    this.unread = 0,
    this.total = 0,
  });

  factory Folder.fromJson(Json j) => Folder(
    name: _str(j, 'name'),
    role: FolderRole.parse(_str(j, 'role')),
    unread: _int(j, 'unread'),
    total: _int(j, 'total'),
  );

  final String name;
  final FolderRole role;
  final int unread;
  final int total;
}

class MessageSummary {
  const MessageSummary({
    required this.id,
    required this.folder,
    required this.from,
    required this.subject,
    required this.date,
    this.to = const [],
    this.seen = false,
    this.flagged = false,
    this.answered = false,
    this.hasAttachments = false,
    this.size = 0,
  });

  factory MessageSummary.fromJson(Json j) => MessageSummary(
    id: _str(j, 'id'),
    folder: _str(j, 'folder'),
    from: j['from'] == null
        ? const Address(email: '')
        : Address.fromJson(j['from']! as Json),
    to: _list(j, 'to', Address.fromJson),
    subject: _str(j, 'subject'),
    date: _time(j, 'date'),
    seen: _bool(j, 'seen'),
    flagged: _bool(j, 'flagged'),
    answered: _bool(j, 'answered'),
    hasAttachments: _bool(j, 'has_attachments'),
    size: _int(j, 'size'),
  );

  final String id;
  final String folder;
  final Address from;
  final List<Address> to;
  final String subject;
  final DateTime date;
  final bool seen;
  final bool flagged;
  final bool answered;
  final bool hasAttachments;
  final int size;

  MessageSummary copyWith({bool? seen, bool? flagged}) => MessageSummary(
    id: id,
    folder: folder,
    from: from,
    to: to,
    subject: subject,
    date: date,
    seen: seen ?? this.seen,
    flagged: flagged ?? this.flagged,
    answered: answered,
    hasAttachments: hasAttachments,
    size: size,
  );
}

class MessagePage {
  const MessagePage({required this.messages, this.nextBefore});

  factory MessagePage.fromJson(Json j) => MessagePage(
    messages: _list(j, 'messages', MessageSummary.fromJson),
    nextBefore: _optStr(j, 'next_before'),
  );

  final List<MessageSummary> messages;
  final String? nextBefore;
}

class AttachmentInfo {
  const AttachmentInfo({
    required this.index,
    required this.filename,
    required this.contentType,
    required this.size,
  });

  factory AttachmentInfo.fromJson(Json j) => AttachmentInfo(
    index: _int(j, 'index'),
    filename: _str(j, 'filename'),
    contentType: _str(j, 'content_type'),
    size: _int(j, 'size'),
  );

  final int index;
  final String filename;
  final String contentType;
  final int size;
}

class Message extends MessageSummary {
  const Message({
    required super.id,
    required super.folder,
    required super.from,
    required super.subject,
    required super.date,
    super.to,
    super.seen,
    super.flagged,
    super.answered,
    super.hasAttachments,
    super.size,
    this.cc = const [],
    this.replyTo = const [],
    this.messageId = '',
    this.inReplyTo = '',
    this.references = const [],
    this.text = '',
    this.html = '',
    this.remoteContentBlocked = false,
    this.attachments = const [],
  });

  factory Message.fromJson(Json j) {
    final s = MessageSummary.fromJson(j);
    return Message(
      id: s.id,
      folder: s.folder,
      from: s.from,
      to: s.to,
      subject: s.subject,
      date: s.date,
      seen: s.seen,
      flagged: s.flagged,
      answered: s.answered,
      hasAttachments: s.hasAttachments,
      size: s.size,
      cc: _list(j, 'cc', Address.fromJson),
      replyTo: _list(j, 'reply_to', Address.fromJson),
      messageId: _str(j, 'message_id'),
      inReplyTo: _str(j, 'in_reply_to'),
      references: _strings(j, 'references'),
      text: _str(j, 'text'),
      html: _str(j, 'html'),
      remoteContentBlocked: _bool(j, 'remote_content_blocked'),
      attachments: _list(j, 'attachments', AttachmentInfo.fromJson),
    );
  }

  final List<Address> cc;
  final List<Address> replyTo;
  final String messageId;
  final String inReplyTo;
  final List<String> references;
  final String text;
  final String html;
  final bool remoteContentBlocked;
  final List<AttachmentInfo> attachments;
}

class OutgoingAttachment {
  const OutgoingAttachment({
    required this.filename,
    required this.contentType,
    required this.dataBase64,
    required this.size,
  });

  final String filename;
  final String contentType;
  final String dataBase64;

  /// Decoded size in bytes. Not sent.
  final int size;

  Json toJson() => {
    'filename': filename,
    'content_type': contentType,
    'data_base64': dataBase64,
  };
}

class OutgoingMessage {
  const OutgoingMessage({
    required this.to,
    required this.subject,
    required this.text,
    this.cc = const [],
    this.bcc = const [],
    this.inReplyTo,
    this.references = const [],
    this.attachments = const [],
  });

  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;
  final String subject;
  final String text;
  final String? inReplyTo;
  final List<String> references;
  final List<OutgoingAttachment> attachments;

  Json toJson() => {
    'to': [for (final a in to) a.toJson()],
    if (cc.isNotEmpty) 'cc': [for (final a in cc) a.toJson()],
    if (bcc.isNotEmpty) 'bcc': [for (final a in bcc) a.toJson()],
    'subject': subject,
    'text': text,
    if (inReplyTo != null && inReplyTo!.isNotEmpty) 'in_reply_to': inReplyTo,
    if (references.isNotEmpty) 'references': references,
    if (attachments.isNotEmpty)
      'attachments': [for (final a in attachments) a.toJson()],
  };
}

// ---------------------------------------------------------------------------
// Calendar

class CalendarInfo {
  const CalendarInfo({required this.id, required this.name, this.color = ''});

  factory CalendarInfo.fromJson(Json j) => CalendarInfo(
    id: _str(j, 'id'),
    name: _str(j, 'name'),
    color: _str(j, 'color'),
  );

  final String id;
  final String name;

  /// CSS-style colour such as `#3366ff`, or empty.
  final String color;
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendar,
    required this.etag,
    required this.summary,
    required this.start,
    required this.end,
    this.uid = '',
    this.description = '',
    this.location = '',
    this.allDay = false,
    this.recurrence = '',
  });

  factory CalendarEvent.fromJson(Json j) => CalendarEvent(
    id: _str(j, 'id'),
    calendar: _str(j, 'calendar'),
    etag: _str(j, 'etag'),
    uid: _str(j, 'uid'),
    summary: _str(j, 'summary'),
    description: _str(j, 'description'),
    location: _str(j, 'location'),
    start: _time(j, 'start'),
    end: _time(j, 'end'),
    allDay: _bool(j, 'all_day'),
    recurrence: _str(j, 'recurrence'),
  );

  final String id;
  final String calendar;
  final String etag;
  final String uid;
  final String summary;
  final String description;
  final String location;

  /// UTC. For all-day events the UTC date part is the calendar date and
  /// [end] is exclusive (the day after the last day).
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// Read-only RRULE text in v1.
  final String recurrence;
}

class EventInput {
  const EventInput({
    required this.calendar,
    required this.summary,
    required this.start,
    required this.end,
    required this.allDay,
    this.id,
    this.etag,
    this.description = '',
    this.location = '',
  });

  final String calendar;
  final String? id;
  final String? etag;
  final String summary;
  final String description;
  final String location;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  Json toJson() => {
    'calendar': calendar,
    if (id != null) 'id': id,
    if (etag != null) 'etag': etag,
    'summary': summary,
    if (description.isNotEmpty) 'description': description,
    if (location.isNotEmpty) 'location': location,
    'start': rfc3339(start),
    'end': rfc3339(end),
    'all_day': allDay,
  };
}

// ---------------------------------------------------------------------------
// Contacts

class AddressBook {
  const AddressBook({required this.id, required this.name});

  factory AddressBook.fromJson(Json j) =>
      AddressBook(id: _str(j, 'id'), name: _str(j, 'name'));

  final String id;
  final String name;
}

class LabeledValue {
  const LabeledValue({required this.value, this.type = ''});

  factory LabeledValue.fromJson(Json j) =>
      LabeledValue(type: _str(j, 'type'), value: _str(j, 'value'));

  final String type;
  final String value;

  Json toJson() => {'type': type, 'value': value};
}

class Contact {
  const Contact({
    required this.id,
    required this.addressbook,
    required this.etag,
    required this.fullName,
    this.uid = '',
    this.emails = const [],
    this.phones = const [],
    this.org = '',
    this.title = '',
    this.note = '',
  });

  factory Contact.fromJson(Json j) => Contact(
    id: _str(j, 'id'),
    addressbook: _str(j, 'addressbook'),
    etag: _str(j, 'etag'),
    uid: _str(j, 'uid'),
    fullName: _str(j, 'full_name'),
    emails: _list(j, 'emails', LabeledValue.fromJson),
    phones: _list(j, 'phones', LabeledValue.fromJson),
    org: _str(j, 'org'),
    title: _str(j, 'title'),
    note: _str(j, 'note'),
  );

  final String id;
  final String addressbook;
  final String etag;
  final String uid;
  final String fullName;
  final List<LabeledValue> emails;
  final List<LabeledValue> phones;
  final String org;
  final String title;
  final String note;

  /// Name to show; falls back to the first email or phone.
  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (emails.isNotEmpty) return emails.first.value;
    if (phones.isNotEmpty) return phones.first.value;
    return '(no name)';
  }
}

class ContactInput {
  const ContactInput({
    required this.addressbook,
    required this.fullName,
    this.id,
    this.etag,
    this.emails = const [],
    this.phones = const [],
    this.org = '',
    this.title = '',
    this.note = '',
  });

  final String addressbook;
  final String? id;
  final String? etag;
  final String fullName;
  final List<LabeledValue> emails;
  final List<LabeledValue> phones;
  final String org;
  final String title;
  final String note;

  Json toJson() => {
    'addressbook': addressbook,
    if (id != null) 'id': id,
    if (etag != null) 'etag': etag,
    'full_name': fullName,
    'emails': [for (final e in emails) e.toJson()],
    'phones': [for (final p in phones) p.toJson()],
    'org': org,
    'title': title,
    'note': note,
  };
}

// ---------------------------------------------------------------------------
// Realtime

class RealtimeEvent {
  const RealtimeEvent({
    required this.type,
    this.accountId = '',
    this.folder = '',
    this.message = '',
  });

  factory RealtimeEvent.fromJson(Json j) => RealtimeEvent(
    type: _str(j, 'type'),
    accountId: _str(j, 'account_id'),
    folder: _str(j, 'folder'),
    message: _str(j, 'message'),
  );

  /// Synthetic event emitted locally after a reconnect or app resume:
  /// anything on screen may be stale and should be re-fetched.
  static const resync = RealtimeEvent(type: 'resync');

  final String type;
  final String accountId;
  final String folder;
  final String message;

  bool get isResync => type == 'resync';
  bool get isMail => type == 'mail.new' || type == 'mail.changed';
}
