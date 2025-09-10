import 'dart:convert';

class EmailModel {
  final String id;
  final String threadId;
  final String subject;
  final String from;
  final String sender;
  final String to;
  final String? cc;
  final String? bcc;
  final DateTime date;
  final String body;
  final String snippet;
  final bool isRead;
  final bool isStarred;
  final bool isImportant;
  final List<String> labels;
  final bool hasAttachments;
  final String? category;
  final Map<String, dynamic>? metadata;
  final int importance;

  EmailModel({
    required this.id,
    required this.threadId,
    required this.subject,
    required this.from,
    required this.to,
    this.cc,
    this.bcc,
    required this.date,
    required this.body,
    required this.snippet,
    this.isRead = false,
    this.isStarred = false,
    this.isImportant = false,
    this.labels = const [],
    this.hasAttachments = false,
    this.category,
    this.metadata,
    this.importance = 0,
  }) : sender = from;

  /// Create EmailModel from JSON
  factory EmailModel.fromJson(Map<String, dynamic> json) {
    return EmailModel(
      id: json['id'] ?? '',
      threadId: json['threadId'] ?? '',
      subject: json['subject'] ?? '',
      from: json['from'] ?? '',
      to: json['to'] ?? '',
      cc: json['cc'],
      bcc: json['bcc'],
      date: json['date'] != null 
          ? DateTime.parse(json['date']) 
          : DateTime.now(),
      body: json['body'] ?? '',
      snippet: json['snippet'] ?? '',
      isRead: json['isRead'] ?? false,
      isStarred: json['isStarred'] ?? false,
      isImportant: json['isImportant'] ?? false,
      labels: List<String>.from(json['labels'] ?? []),
      hasAttachments: json['hasAttachments'] ?? false,
      category: json['category'],
      metadata: json['metadata'],
      importance: json['importance'] ?? 0,
    );
  }

  /// Convert EmailModel to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'threadId': threadId,
      'subject': subject,
      'from': from,
      'to': to,
      'cc': cc,
      'bcc': bcc,
      'date': date.toIso8601String(),
      'body': body,
      'snippet': snippet,
      'isRead': isRead,
      'isStarred': isStarred,
      'isImportant': isImportant,
      'labels': labels,
      'hasAttachments': hasAttachments,
      'category': category,
      'metadata': metadata,
      'importance': importance,
    };
  }

  /// Create a copy with updated fields
  EmailModel copyWith({
    String? id,
    String? threadId,
    String? subject,
    String? from,
    String? to,
    String? cc,
    String? bcc,
    DateTime? date,
    String? body,
    String? snippet,
    bool? isRead,
    bool? isStarred,
    bool? isImportant,
    List<String>? labels,
    bool? hasAttachments,
    String? category,
    Map<String, dynamic>? metadata,
    int? importance,
  }) {
    return EmailModel(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      subject: subject ?? this.subject,
      from: from ?? this.from,
      to: to ?? this.to,
      cc: cc ?? this.cc,
      bcc: bcc ?? this.bcc,
      date: date ?? this.date,
      body: body ?? this.body,
      snippet: snippet ?? this.snippet,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      isImportant: isImportant ?? this.isImportant,
      labels: labels ?? this.labels,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      category: category ?? this.category,
      metadata: metadata ?? this.metadata,
      importance: importance ?? this.importance,
    );
  }

  /// Get sender name from email address
  String get senderName {
    final match = RegExp(r'"?([^"<]+)"?\s*<').firstMatch(from);
    if (match != null) {
      return match.group(1)?.trim() ?? from;
    }
    return from.split('@').first;
  }

  /// Get sender email address only
  String get senderEmail {
    final match = RegExp(r'<([^>]+)>').firstMatch(from);
    if (match != null) {
      return match.group(1) ?? from;
    }
    return from;
  }

  /// Get formatted date string
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      // Today - show time
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    } else {
      // Older - show date
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Get plain text body (strip HTML)
  String get plainTextBody {
    return body
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  /// Check if email is from a specific domain
  bool isFromDomain(String domain) {
    return senderEmail.toLowerCase().endsWith('@${domain.toLowerCase()}');
  }

  /// Get priority level based on labels and content
  int get priority {
    if (isImportant || labels.contains('IMPORTANT')) return 3;
    if (isStarred || labels.contains('STARRED')) return 2;
    if (labels.contains('CATEGORY_PERSONAL')) return 1;
    return 0;
  }

  @override
  String toString() {
    return 'EmailModel(id: $id, subject: $subject, from: $from, date: $date)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EmailModel &&
        other.id == id &&
        other.threadId == threadId;
  }

  @override
  int get hashCode {
    return id.hashCode ^ threadId.hashCode;
  }
}

/// Email sorting options
enum EmailSortBy {
  date,
  sender,
  subject,
  importance,
  read,
}

/// Email filter options
class EmailFilter {
  final bool? isRead;
  final bool? isStarred;
  final bool? isImportant;
  final bool? hasAttachments;
  final String? category;
  final String? sender;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<String>? labels;

  EmailFilter({
    this.isRead,
    this.isStarred,
    this.isImportant,
    this.hasAttachments,
    this.category,
    this.sender,
    this.dateFrom,
    this.dateTo,
    this.labels,
  });

  /// Check if email matches this filter
  bool matches(EmailModel email) {
    if (isRead != null && email.isRead != isRead) return false;
    if (isStarred != null && email.isStarred != isStarred) return false;
    if (isImportant != null && email.isImportant != isImportant) return false;
    if (hasAttachments != null && email.hasAttachments != hasAttachments) return false;
    if (category != null && email.category != category) return false;
    if (sender != null && !email.senderEmail.toLowerCase().contains(sender!.toLowerCase())) return false;
    if (dateFrom != null && email.date.isBefore(dateFrom!)) return false;
    if (dateTo != null && email.date.isAfter(dateTo!)) return false;
    if (labels != null && !labels!.any((label) => email.labels.contains(label))) return false;
    
    return true;
  }
}