# AI Mail Client

An intelligent email management application powered by AI, built with Flutter. This app provides smart email categorization, analysis, and management features with a modern, intuitive interface.

## Features

🔐 **Secure Authentication**
- OAuth 2.0 integration with Google Sign-In
- Secure token management with local storage

📧 **Gmail Integration**
- Full Gmail API integration
- Read, search, and manage emails
- Batch email processing
- Label management

🤖 **AI-Powered Analysis**
- Automatic email categorization (Work, Personal, Promotions, Social, Spam)
- Content extraction (dates, names, phone numbers, URLs)
- Sentiment analysis
- Importance scoring
- Email statistics and insights

📱 **Modern UI/UX**
- Material Design 3 with dynamic theming
- Dark/Light mode support
- Responsive design for all screen sizes
- Smooth animations and transitions

🔧 **Advanced Features**
- Smart filtering and sorting
- Visual analytics dashboard
- Bulk email operations
- Offline data persistence
- Cross-platform support (iOS, Android, Web, Desktop)

## Quick Start

### Prerequisites
- Flutter SDK (latest stable version)
- Dart SDK
- iOS development: Xcode and iOS Simulator
- Android development: Android Studio and Android SDK

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd optional_mail_client
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Set up Google OAuth 2.0**
   - Follow the detailed setup guide in [SETUP_GUIDE.md](SETUP_GUIDE.md)
   - Configure your Google Cloud project
   - Add your client IDs to the app configuration

4. **Run the app**
   ```bash
   flutter run
   ```

## Configuration

⚠️ **Important**: Before running the app, you must configure Google OAuth 2.0 credentials.

See [SETUP_GUIDE.md](SETUP_GUIDE.md) for detailed configuration instructions.

## Project Structure

```
lib/
├── constants/          # App constants and configuration
├── models/            # Data models (User, Email)
├── services/          # Business logic (Auth, Gmail, Analysis)
├── screens/           # UI screens (Splash, Auth, Home)
├── widgets/           # Reusable UI components
├── providers/         # State management (Riverpod)
└── utils/            # Utility functions
```

## Key Technologies

- **Flutter**: Cross-platform UI framework
- **Riverpod**: State management
- **Hive**: Local data storage
- **Google Sign-In**: Authentication
- **Gmail API**: Email operations
- **Material Design 3**: Modern UI components
- **FL Chart**: Data visualization

## Development

### Running Tests
```bash
flutter test
```

### Building for Production

**iOS:**
```bash
flutter build ios --release
```

**Android:**
```bash
flutter build apk --release
```

**Web:**
```bash
flutter build web --release
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For setup issues, see [SETUP_GUIDE.md](SETUP_GUIDE.md)

For other questions or issues, please create an issue in the repository.
