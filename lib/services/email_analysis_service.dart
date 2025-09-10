import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../models/email_model.dart';

class EmailAnalysisService {
  static final EmailAnalysisService _instance = EmailAnalysisService._internal();
  factory EmailAnalysisService() => _instance;
  EmailAnalysisService._internal();

  // Keywords for different categories
  final Map<String, List<String>> _categoryKeywords = {
    'Work': [
      'meeting', 'project', 'deadline', 'report', 'presentation', 'conference',
      'team', 'manager', 'client', 'proposal', 'budget', 'schedule', 'task',
      'urgent', 'asap', 'follow up', 'action required', 'review', 'approval'
    ],
    'Personal': [
      'family', 'friend', 'birthday', 'vacation', 'weekend', 'dinner', 'party',
      'wedding', 'anniversary', 'holiday', 'personal', 'private', 'home'
    ],
    'Promotions': [
      'sale', 'discount', 'offer', 'deal', 'coupon', 'promotion', 'limited time',
      'free shipping', 'buy now', 'save', 'special offer', 'clearance', 'promo'
    ],
    'Social': [
      'facebook', 'twitter', 'instagram', 'linkedin', 'notification', 'comment',
      'like', 'share', 'follow', 'friend request', 'message', 'post', 'update'
    ],
    'Updates': [
      'newsletter', 'update', 'news', 'announcement', 'release', 'version',
      'changelog', 'notification', 'alert', 'reminder', 'subscription'
    ],
    'Forums': [
      'forum', 'discussion', 'thread', 'reply', 'post', 'community', 'group',
      'board', 'topic', 'question', 'answer', 'help', 'support'
    ],
  };

  // Important keywords that indicate high priority
  final List<String> _importantKeywords = [
    'urgent', 'asap', 'important', 'critical', 'emergency', 'immediate',
    'deadline', 'action required', 'time sensitive', 'priority', 'escalation'
  ];

  // Spam indicators
  final List<String> _spamKeywords = [
    'viagra', 'casino', 'lottery', 'winner', 'congratulations', 'claim now',
    'act now', 'limited time', 'make money', 'work from home', 'free money',
    'click here', 'unsubscribe', 'remove me', 'opt out'
  ];

  /// Analyze and categorize a single email
  Future<EmailModel> analyzeEmail(EmailModel email) async {
    try {
      // Determine category
      final category = _categorizeEmail(email);
      
      // Extract key information
      final metadata = await _extractKeyInformation(email);
      
      // Determine importance
      final isImportant = _determineImportance(email);
      
      return email.copyWith(
        category: category,
        metadata: metadata,
        isImportant: isImportant,
      );
    } catch (e) {
      debugPrint('Error analyzing email ${email.id}: $e');
      return email;
    }
  }

  /// Analyze multiple emails in batch
  Future<List<EmailModel>> analyzeEmails(List<EmailModel> emails) async {
    try {
      final futures = emails.map((email) => analyzeEmail(email));
      return await Future.wait(futures);
    } catch (e) {
      debugPrint('Error analyzing emails batch: $e');
      return emails;
    }
  }

  /// Categorize email based on content and sender
  String _categorizeEmail(EmailModel email) {
    final content = '${email.subject} ${email.body} ${email.from}'.toLowerCase();
    
    // Check for spam first
    if (_containsKeywords(content, _spamKeywords)) {
      return 'Spam';
    }
    
    // Score each category
    final scores = <String, int>{};
    
    for (final category in _categoryKeywords.keys) {
      final keywords = _categoryKeywords[category]!;
      scores[category] = _countKeywords(content, keywords);
    }
    
    // Additional heuristics
    _applyHeuristics(email, scores);
    
    // Find category with highest score
    if (scores.values.every((score) => score == 0)) {
      return 'Personal'; // Default category
    }
    
    final maxScore = scores.values.reduce(max);
    return scores.entries
        .firstWhere((entry) => entry.value == maxScore)
        .key;
  }

  /// Apply additional heuristics for categorization
  void _applyHeuristics(EmailModel email, Map<String, int> scores) {
    final senderEmail = email.senderEmail.toLowerCase();
    final senderDomain = senderEmail.split('@').last;
    
    // Work emails
    if (senderDomain.contains('company') || 
        senderDomain.contains('corp') ||
        senderEmail.contains('noreply') ||
        senderEmail.contains('no-reply')) {
      scores['Work'] = (scores['Work'] ?? 0) + 2;
    }
    
    // Promotional emails
    if (senderEmail.contains('marketing') ||
        senderEmail.contains('promo') ||
        senderEmail.contains('deals') ||
        email.subject.toLowerCase().contains('unsubscribe')) {
      scores['Promotions'] = (scores['Promotions'] ?? 0) + 3;
    }
    
    // Social media
    if (senderDomain.contains('facebook') ||
        senderDomain.contains('twitter') ||
        senderDomain.contains('instagram') ||
        senderDomain.contains('linkedin')) {
      scores['Social'] = (scores['Social'] ?? 0) + 5;
    }
    
    // Updates/Newsletters
    if (senderEmail.contains('newsletter') ||
        senderEmail.contains('updates') ||
        email.subject.toLowerCase().contains('newsletter')) {
      scores['Updates'] = (scores['Updates'] ?? 0) + 3;
    }
  }

  /// Extract key information from email content
  Future<Map<String, dynamic>> _extractKeyInformation(EmailModel email) async {
    final metadata = <String, dynamic>{};
    
    // Extract dates
    final dates = _extractDates(email.body);
    if (dates.isNotEmpty) {
      metadata['mentioned_dates'] = dates.map((d) => d.toIso8601String()).toList();
    }
    
    // Extract names
    final names = _extractNames(email.body);
    if (names.isNotEmpty) {
      metadata['mentioned_names'] = names;
    }
    
    // Extract phone numbers
    final phoneNumbers = _extractPhoneNumbers(email.body);
    if (phoneNumbers.isNotEmpty) {
      metadata['phone_numbers'] = phoneNumbers;
    }
    
    // Extract URLs
    final urls = _extractUrls(email.body);
    if (urls.isNotEmpty) {
      metadata['urls'] = urls;
    }
    
    // Extract email addresses
    final emailAddresses = _extractEmailAddresses(email.body);
    if (emailAddresses.isNotEmpty) {
      metadata['email_addresses'] = emailAddresses;
    }
    
    // Sentiment analysis (basic)
    metadata['sentiment'] = _analyzeSentiment(email.body);
    
    // Word count and reading time
    final wordCount = email.plainTextBody.split(RegExp(r'\s+')).length;
    metadata['word_count'] = wordCount;
    metadata['reading_time_minutes'] = (wordCount / 200).ceil(); // Average reading speed
    
    return metadata;
  }

  /// Determine if email is important
  bool _determineImportance(EmailModel email) {
    final content = '${email.subject} ${email.body}'.toLowerCase();
    
    // Check for important keywords
    if (_containsKeywords(content, _importantKeywords)) {
      return true;
    }
    
    // Check if from known important senders (this could be user-configurable)
    final importantDomains = ['boss', 'manager', 'ceo', 'director'];
    if (importantDomains.any((domain) => email.senderEmail.toLowerCase().contains(domain))) {
      return true;
    }
    
    // Check if already marked as important by Gmail
    if (email.labels.contains('IMPORTANT')) {
      return true;
    }
    
    return false;
  }

  /// Extract dates from text
  List<DateTime> _extractDates(String text) {
    final dates = <DateTime>[];
    
    // Simple date patterns (can be enhanced)
    final datePatterns = [
      RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b'), // MM/DD/YYYY
      RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'), // YYYY-MM-DD
      RegExp(r'\b(\d{1,2})-(\d{1,2})-(\d{4})\b'), // DD-MM-YYYY
    ];
    
    for (final pattern in datePatterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        try {
          DateTime? date;
          if (pattern == datePatterns[0]) { // MM/DD/YYYY
            date = DateTime(int.parse(match.group(3)!), int.parse(match.group(1)!), int.parse(match.group(2)!));
          } else if (pattern == datePatterns[1]) { // YYYY-MM-DD
            date = DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!));
          } else { // DD-MM-YYYY
            date = DateTime(int.parse(match.group(3)!), int.parse(match.group(2)!), int.parse(match.group(1)!));
          }
          if (date != null) dates.add(date);
        } catch (e) {
          // Invalid date, skip
        }
      }
    }
    
    return dates;
  }

  /// Extract names from text (basic implementation)
  List<String> _extractNames(String text) {
    final names = <String>[];
    
    // Simple pattern for capitalized words (potential names)
    final namePattern = RegExp(r'\b[A-Z][a-z]+ [A-Z][a-z]+\b');
    final matches = namePattern.allMatches(text);
    
    for (final match in matches) {
      final name = match.group(0)!;
      if (!names.contains(name)) {
        names.add(name);
      }
    }
    
    return names;
  }

  /// Extract phone numbers
  List<String> _extractPhoneNumbers(String text) {
    final phoneNumbers = <String>[];
    
    final phonePatterns = [
      RegExp(r'\b\d{3}-\d{3}-\d{4}\b'), // XXX-XXX-XXXX
      RegExp(r'\b\(\d{3}\)\s*\d{3}-\d{4}\b'), // (XXX) XXX-XXXX
      RegExp(r'\b\d{10}\b'), // XXXXXXXXXX
    ];
    
    for (final pattern in phonePatterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        final phone = match.group(0)!;
        if (!phoneNumbers.contains(phone)) {
          phoneNumbers.add(phone);
        }
      }
    }
    
    return phoneNumbers;
  }

  /// Extract URLs
  List<String> _extractUrls(String text) {
    final urls = <String>[];
    
    final urlPattern = RegExp(r'https?://[^\s]+');
    final matches = urlPattern.allMatches(text);
    
    for (final match in matches) {
      final url = match.group(0)!;
      if (!urls.contains(url)) {
        urls.add(url);
      }
    }
    
    return urls;
  }

  /// Extract email addresses
  List<String> _extractEmailAddresses(String text) {
    final emails = <String>[];
    
    final emailPattern = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b');
    final matches = emailPattern.allMatches(text);
    
    for (final match in matches) {
      final email = match.group(0)!;
      if (!emails.contains(email)) {
        emails.add(email);
      }
    }
    
    return emails;
  }

  /// Basic sentiment analysis
  String _analyzeSentiment(String text) {
    final positiveWords = ['good', 'great', 'excellent', 'amazing', 'wonderful', 'fantastic', 'love', 'like', 'happy', 'pleased'];
    final negativeWords = ['bad', 'terrible', 'awful', 'hate', 'dislike', 'angry', 'frustrated', 'disappointed', 'sad', 'upset'];
    
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    
    int positiveCount = 0;
    int negativeCount = 0;
    
    for (final word in words) {
      if (positiveWords.contains(word)) positiveCount++;
      if (negativeWords.contains(word)) negativeCount++;
    }
    
    if (positiveCount > negativeCount) return 'positive';
    if (negativeCount > positiveCount) return 'negative';
    return 'neutral';
  }

  /// Count keywords in content
  int _countKeywords(String content, List<String> keywords) {
    int count = 0;
    for (final keyword in keywords) {
      if (content.contains(keyword.toLowerCase())) {
        count++;
      }
    }
    return count;
  }

  /// Check if content contains any of the keywords
  bool _containsKeywords(String content, List<String> keywords) {
    return keywords.any((keyword) => content.contains(keyword.toLowerCase()));
  }

  /// Categorize a single email
  String categorizeEmail(EmailModel email) {
    final subject = email.subject.toLowerCase();
    final body = (email.body ?? email.snippet).toLowerCase();
    final sender = email.from.toLowerCase();

    // Check for spam indicators
    if (_isSpam(email)) {
      return 'Spam';
    }

    // Check for work-related emails
    if (_workKeywords.any((keyword) => subject.contains(keyword) || body.contains(keyword)) ||
        sender.contains('noreply') ||
        sender.contains('no-reply')) {
      return 'Work';
    }

    // Check for promotional emails
    if (_promotionalKeywords.any((keyword) => subject.contains(keyword) || body.contains(keyword)) ||
        subject.contains('unsubscribe') ||
        body.contains('unsubscribe')) {
      return 'Promotions';
    }

    // Check for social emails
    if (_socialKeywords.any((keyword) => subject.contains(keyword) || body.contains(keyword)) ||
        _socialDomains.any((domain) => sender.contains(domain))) {
      return 'Social';
    }

    // Check for important emails
    if (email.isStarred || _importantKeywords.any((keyword) => subject.contains(keyword))) {
      return 'Important';
    }

    return 'Personal';
  }

  /// Get category statistics
  Map<String, int> getCategoryStats(List<EmailModel> emails) {
    final stats = <String, int>{};
    
    for (final email in emails) {
      final category = email.category ?? 'Other';
      stats[category] = (stats[category] ?? 0) + 1;
    }
    
    return stats;
  }

  /// Generate email statistics
  Map<String, dynamic> generateEmailStats(List<EmailModel> emails) {
    if (emails.isEmpty) {
      return {
        'totalEmails': 0,
        'unreadEmails': 0,
        'categories': <String, int>{},
        'topSenders': <String, int>{},
        'emailsPerDay': <String, int>{},
        'averageEmailsPerDay': 0.0,
      };
    }

    final categories = <String, int>{};
    final senders = <String, int>{};
    final emailsPerDay = <String, int>{};
    int unreadCount = 0;

    for (final email in emails) {
      // Count categories
      final category = email.category ?? 'Other';
      categories[category] = (categories[category] ?? 0) + 1;

      // Count senders
      final sender = _extractSenderName(email.from);
      senders[sender] = (senders[sender] ?? 0) + 1;

      // Count emails per day
      final dayKey = '${email.date.year}-${email.date.month.toString().padLeft(2, '0')}-${email.date.day.toString().padLeft(2, '0')}';
      emailsPerDay[dayKey] = (emailsPerDay[dayKey] ?? 0) + 1;

      // Count unread
      if (!email.isRead) {
        unreadCount++;
      }
    }

    // Get top 10 senders
    final topSenders = Map.fromEntries(
      senders.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..take(10),
    );

    // Calculate average emails per day
    final totalDays = emailsPerDay.length;
    final averageEmailsPerDay = totalDays > 0 ? emails.length / totalDays : 0.0;

    return {
      'totalEmails': emails.length,
      'unreadEmails': unreadCount,
      'categories': categories,
      'topSenders': topSenders,
      'emailsPerDay': emailsPerDay,
      'averageEmailsPerDay': averageEmailsPerDay,
    };
  }

  /// Get email statistics for visualization
  Map<String, dynamic> getEmailStatistics(List<EmailModel> emails) {
    final stats = <String, dynamic>{};
    
    // Category distribution
    final categoryCount = <String, int>{};
    for (final email in emails) {
      final category = email.category ?? 'Uncategorized';
      categoryCount[category] = (categoryCount[category] ?? 0) + 1;
    }
    stats['category_distribution'] = categoryCount;
    
    // Sender frequency
    final senderCount = <String, int>{};
    for (final email in emails) {
      final sender = email.senderName;
      senderCount[sender] = (senderCount[sender] ?? 0) + 1;
    }
    stats['top_senders'] = senderCount.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..take(10);
    
    // Daily email count
    final dailyCount = <String, int>{};
    for (final email in emails) {
      final dateKey = '${email.date.year}-${email.date.month.toString().padLeft(2, '0')}-${email.date.day.toString().padLeft(2, '0')}';
      dailyCount[dateKey] = (dailyCount[dateKey] ?? 0) + 1;
    }
    stats['daily_count'] = dailyCount;
    
    // Read/Unread ratio
    final readCount = emails.where((e) => e.isRead).length;
    final unreadCount = emails.length - readCount;
    stats['read_unread_ratio'] = {'read': readCount, 'unread': unreadCount};
    
    // Important emails count
    final importantCount = emails.where((e) => e.isImportant).length;
    stats['important_count'] = importantCount;
    
    return stats;
  }

  /// Helper method to check if email is spam
  bool _isSpam(EmailModel email) {
    final content = '${email.subject} ${email.body}'.toLowerCase();
    return _containsKeywords(content, _spamKeywords);
  }

  /// Helper method to extract sender name from email address
  String _extractSenderName(String fromField) {
    // Extract name from "Name <email@domain.com>" format
    final nameMatch = RegExp(r'^([^<]+)<').firstMatch(fromField);
    if (nameMatch != null) {
      return nameMatch.group(1)!.trim();
    }
    
    // If no name found, use email address
    final emailMatch = RegExp(r'[\w\.-]+@[\w\.-]+').firstMatch(fromField);
    if (emailMatch != null) {
      return emailMatch.group(0)!;
    }
    
    return fromField;
  }

  /// Additional keyword lists for the new categorize method
  final List<String> _workKeywords = [
    'meeting', 'project', 'deadline', 'report', 'presentation', 'conference',
    'team', 'manager', 'client', 'proposal', 'budget', 'schedule', 'task'
  ];

  final List<String> _promotionalKeywords = [
    'sale', 'discount', 'offer', 'deal', 'coupon', 'promotion', 'limited time',
    'free shipping', 'buy now', 'save', 'special offer', 'clearance'
  ];

  final List<String> _socialKeywords = [
    'facebook', 'twitter', 'instagram', 'linkedin', 'notification', 'comment',
    'like', 'share', 'follow', 'friend request', 'message', 'post'
  ];

  final List<String> _socialDomains = [
    'facebook.com', 'twitter.com', 'instagram.com', 'linkedin.com'
  ];
}