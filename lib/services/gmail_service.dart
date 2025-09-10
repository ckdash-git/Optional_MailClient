import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../models/email_model.dart';
import '../services/auth_service.dart';

class GmailService {
  static final GmailService _instance = GmailService._internal();
  factory GmailService() => _instance;
  GmailService._internal();

  final AuthService _authService = AuthService();
  gmail.GmailApi? _gmailApi;

  /// Initialize Gmail API
  Future<bool> initialize() async {
    try {
      final authClient = _authService.authClient;
      if (authClient != null) {
        _gmailApi = gmail.GmailApi(authClient);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error initializing Gmail service: $e');
      return false;
    }
  }

  /// Get user's email messages with pagination
  Future<List<EmailModel>> getEmails({
    String? query,
    int maxResults = 50,
    String? pageToken,
  }) async {
    try {
      if (_gmailApi == null) {
        final initialized = await initialize();
        if (!initialized) {
          throw Exception('Failed to initialize Gmail API');
        }
      }

      final response = await _gmailApi!.users.messages.list(
        'me',
        q: query,
        maxResults: maxResults,
        pageToken: pageToken,
      );

      if (response.messages == null || response.messages!.isEmpty) {
        return [];
      }

      // Fetch detailed information for each message sequentially to avoid rate limiting
      final List<EmailModel> emails = [];
      for (final message in response.messages!) {
        try {
          final detailedMessage = await _gmailApi!.users.messages.get(
            'me',
            message.id!,
            format: 'full',
          );
          final email = _parseEmailFromMessage(detailedMessage);
          if (email != null) {
            emails.add(email);
          }
          // Add small delay to avoid rate limiting
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint('Error fetching message ${message.id}: $e');
        }
      }

      return emails;
    } catch (e) {
      debugPrint('Error getting emails: $e');
      return [];
    }
  }

  /// Search emails with specific criteria
  Future<List<EmailModel>> searchEmails({
    String? from,
    String? to,
    String? subject,
    String? body,
    DateTime? after,
    DateTime? before,
    bool? hasAttachment,
    String? label,
  }) async {
    final queryParts = <String>[];

    if (from != null && from.isNotEmpty) {
      queryParts.add('from:$from');
    }
    if (to != null && to.isNotEmpty) {
      queryParts.add('to:$to');
    }
    if (subject != null && subject.isNotEmpty) {
      queryParts.add('subject:$subject');
    }
    if (body != null && body.isNotEmpty) {
      queryParts.add('$body');
    }
    if (after != null) {
      final afterStr = '${after.year}/${after.month}/${after.day}';
      queryParts.add('after:$afterStr');
    }
    if (before != null) {
      final beforeStr = '${before.year}/${before.month}/${before.day}';
      queryParts.add('before:$beforeStr');
    }
    if (hasAttachment == true) {
      queryParts.add('has:attachment');
    }
    if (label != null && label.isNotEmpty) {
      queryParts.add('label:$label');
    }

    final query = queryParts.join(' ');
    return await getEmails(query: query);
  }

  /// Get emails by category/label
  Future<List<EmailModel>> getEmailsByCategory(String category) async {
    final labelMap = {
      'inbox': 'INBOX',
      'sent': 'SENT',
      'drafts': 'DRAFT',
      'spam': 'SPAM',
      'trash': 'TRASH',
      'important': 'IMPORTANT',
      'starred': 'STARRED',
    };

    final label = labelMap[category.toLowerCase()] ?? category;
    return await getEmails(query: 'label:$label');
  }

  /// Mark email as read/unread
  Future<bool> markAsRead(String messageId, bool isRead) async {
    try {
      if (_gmailApi == null) {
        await initialize();
      }

      final request = gmail.ModifyMessageRequest();
      if (isRead) {
        request.removeLabelIds = ['UNREAD'];
      } else {
        request.addLabelIds = ['UNREAD'];
      }

      await _gmailApi!.users.messages.modify(request, 'me', messageId);
      return true;
    } catch (e) {
      debugPrint('Error marking message as read: $e');
      return false;
    }
  }

  /// Add/remove labels from email
  Future<bool> modifyLabels(String messageId, {
    List<String>? addLabels,
    List<String>? removeLabels,
  }) async {
    try {
      if (_gmailApi == null) {
        await initialize();
      }

      final request = gmail.ModifyMessageRequest();
      if (addLabels != null && addLabels.isNotEmpty) {
        request.addLabelIds = addLabels;
      }
      if (removeLabels != null && removeLabels.isNotEmpty) {
        request.removeLabelIds = removeLabels;
      }

      await _gmailApi!.users.messages.modify(request, 'me', messageId);
      return true;
    } catch (e) {
      debugPrint('Error modifying labels: $e');
      return false;
    }
  }

  /// Delete email (move to trash)
  Future<bool> deleteEmail(String messageId) async {
    try {
      if (_gmailApi == null) {
        await initialize();
      }

      await _gmailApi!.users.messages.trash('me', messageId);
      return true;
    } catch (e) {
      debugPrint('Error deleting email: $e');
      return false;
    }
  }

  /// Get user's labels
  Future<List<gmail.Label>> getLabels() async {
    try {
      if (_gmailApi == null) {
        await initialize();
      }

      final response = await _gmailApi!.users.labels.list('me');
      return response.labels ?? [];
    } catch (e) {
      debugPrint('Error getting labels: $e');
      return [];
    }
  }

  /// Parse Gmail message to EmailModel
  EmailModel _parseEmailFromMessage(gmail.Message message) {
    final headers = message.payload?.headers ?? [];
    
    String getHeader(String name) {
      final header = headers.firstWhere(
        (h) => h.name?.toLowerCase() == name.toLowerCase(),
        orElse: () => gmail.MessagePartHeader(),
      );
      return header.value ?? '';
    }

    // Extract body content
    String body = '';
    if (message.payload?.body?.data != null) {
      body = utf8.decode(base64Url.decode(message.payload!.body!.data!));
    } else if (message.payload?.parts != null) {
      for (final part in message.payload!.parts!) {
        if (part.mimeType == 'text/plain' || part.mimeType == 'text/html') {
          if (part.body?.data != null) {
            body = utf8.decode(base64Url.decode(part.body!.data!));
            break;
          }
        }
      }
    }

    // Parse date
    DateTime? date;
    final dateStr = getHeader('date');
    if (dateStr.isNotEmpty) {
      try {
        date = DateTime.parse(dateStr);
      } catch (e) {
        // Try parsing with different format if needed
        date = DateTime.now();
      }
    }

    return EmailModel(
      id: message.id ?? '',
      threadId: message.threadId ?? '',
      subject: getHeader('subject'),
      from: getHeader('from'),
      to: getHeader('to'),
      cc: getHeader('cc'),
      bcc: getHeader('bcc'),
      date: date ?? DateTime.now(),
      body: body,
      snippet: message.snippet ?? '',
      isRead: !(message.labelIds?.contains('UNREAD') ?? false),
      isStarred: message.labelIds?.contains('STARRED') ?? false,
      isImportant: message.labelIds?.contains('IMPORTANT') ?? false,
      labels: message.labelIds ?? [],
      hasAttachments: message.payload?.parts?.any(
        (part) => part.filename != null && part.filename!.isNotEmpty,
      ) ?? false,
    );
  }

  /// Batch operations for multiple emails
  Future<bool> batchMarkAsRead(List<String> messageIds, bool isRead) async {
    try {
      final futures = messageIds.map((id) => markAsRead(id, isRead));
      final results = await Future.wait(futures);
      return results.every((result) => result);
    } catch (e) {
      debugPrint('Error in batch mark as read: $e');
      return false;
    }
  }

  /// Batch delete emails
  Future<bool> batchDeleteEmails(List<String> messageIds) async {
    try {
      final futures = messageIds.map((id) => deleteEmail(id));
      final results = await Future.wait(futures);
      return results.every((result) => result);
    } catch (e) {
      debugPrint('Error in batch delete: $e');
      return false;
    }
  }
}