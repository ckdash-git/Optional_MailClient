class AppConstants {
  // OAuth 2.0 Configuration
  static const String clientId = '527193526235-coqfbfbp5thkum7fg0cdovt6vob9gh83.apps.googleusercontent.com'; // Replace with actual client ID
  static const String clientSecret = 'YOUR_GOOGLE_CLIENT_SECRET'; // Replace with actual client secret
  
  // Gmail API Scopes
  static const List<String> scopes = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.modify',
    'https://www.googleapis.com/auth/gmail.labels',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];
  
  // App Configuration
  static const String appName = 'Optional MailClient';
  static const String appVersion = '1.0.0';
  
  // Storage Keys
  static const String userTokenKey = 'user_token';
  static const String userInfoKey = 'user_info';
  static const String emailCacheKey = 'email_cache';
  static const String settingsKey = 'app_settings';
  
  // Email Categories
  static const List<String> emailCategories = [
    'Personal',
    'Work',
    'Promotions',
    'Social',
    'Updates',
    'Forums',
    'Spam',
    'Important',
  ];
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  
  // Performance Settings
  static const int emailBatchSize = 50;
  static const int maxCachedEmails = 1000;
  static const Duration cacheExpiration = Duration(hours: 1);
  static const int maxConcurrentRequests = 5;
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxRetryAttempts = 3;
  static const int defaultEmailBatchSize = 50;
}