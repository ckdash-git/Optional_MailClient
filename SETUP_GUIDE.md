# AI Mail Client - Setup Guide

## Google OAuth 2.0 Configuration

To use this AI Mail Client, you need to set up Google OAuth 2.0 credentials. Follow these steps:

### 1. Create a Google Cloud Project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the Gmail API:
   - Go to "APIs & Services" > "Library"
   - Search for "Gmail API" and enable it

### 2. Create OAuth 2.0 Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth 2.0 Client IDs"
3. Configure the OAuth consent screen if prompted
4. Create credentials for each platform:

#### For iOS:
- Application type: iOS
- Bundle ID: `com.Optional.MailClient` (or your custom bundle ID)

#### For Android:
- Application type: Android
- Package name: `com.Optional.MailClient`
- SHA-1 certificate fingerprint: (get from your keystore)

#### For Web:
- Application type: Web application
- Authorized redirect URIs: `http://localhost` (for development)

### 3. Configure the App

#### Update iOS Configuration:
1. Open `/ios/Runner/Info.plist`
2. Replace `YOUR_GOOGLE_CLIENT_ID` with your iOS client ID
3. Replace `YOUR_REVERSED_CLIENT_ID` with your reversed client ID (e.g., `com.googleusercontent.apps.123456789`)

#### Update Android Configuration:
1. Create `/android/app/google-services.json` with your Google Services configuration
2. Or manually add the client ID to your Android configuration

#### Update App Constants:
1. Open `/lib/constants/app_constants.dart`
2. Replace `YOUR_GOOGLE_CLIENT_ID` with your actual client ID
3. Replace `YOUR_GOOGLE_CLIENT_SECRET` with your client secret (if needed)

### 4. Required Scopes

The app requests these Gmail API scopes:
- `https://www.googleapis.com/auth/gmail.readonly` - Read emails
- `https://www.googleapis.com/auth/gmail.modify` - Modify emails (mark as read, etc.)
- `https://www.googleapis.com/auth/gmail.labels` - Manage labels
- `https://www.googleapis.com/auth/userinfo.email` - User email
- `https://www.googleapis.com/auth/userinfo.profile` - User profile

### 5. Testing

1. Add your test email addresses to the OAuth consent screen test users
2. Run the app: `flutter run`
3. Test the Google Sign-In functionality

### 6. Production Deployment

1. Verify your domain in Google Cloud Console
2. Submit your app for OAuth verification if needed
3. Update redirect URIs for production domains
4. Use production-ready client IDs and secrets

## Troubleshooting

### Common Issues:

1. **"No active configuration" error**:
   - Ensure GIDClientID is set in Info.plist (iOS)
   - Ensure google-services.json is added (Android)

2. **"Invalid client" error**:
   - Check that client ID matches the platform
   - Verify bundle ID/package name matches Google Console

3. **"Access denied" error**:
   - Add test users to OAuth consent screen
   - Check that required scopes are enabled

4. **Build errors**:
   - Run `flutter clean && flutter pub get`
   - For iOS: `cd ios && pod install`

## Security Notes

- Never commit actual client IDs/secrets to version control
- Use environment variables or secure configuration management
- Regularly rotate credentials
- Monitor API usage in Google Cloud Console

## Support

For additional help:
- [Google Sign-In Flutter Plugin Documentation](https://pub.dev/packages/google_sign_in)
- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [Google Cloud Console](https://console.cloud.google.com/)