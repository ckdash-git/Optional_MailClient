import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  GoogleSignIn? _googleSignIn;
  GoogleSignInAccount? _currentUser;
  AuthClient? _authClient;
  bool _isAuthenticated = false;
  bool _isLoading = false;

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  GoogleSignInAccount? get currentUser => _currentUser;
  AuthClient? get authClient => _authClient;

  /// Initialize the authentication service
  Future<void> initialize() async {
    try {
      _setLoading(true);
      
      _googleSignIn = GoogleSignIn(
        scopes: AppConstants.scopes,
        serverClientId: AppConstants.clientId,
      );

      // Check if user is already signed in
      await _checkExistingAuth();
    } catch (e) {
      debugPrint('Error initializing auth service: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Check for existing authentication
  Future<void> _checkExistingAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(AppConstants.userTokenKey);
      
      if (savedToken != null) {
        // Try to restore session
        final account = await _googleSignIn?.signInSilently();
        if (account != null) {
          await _handleSignInSuccess(account);
        }
      }
    } catch (e) {
      debugPrint('Error checking existing auth: $e');
    }
  }

  /// Sign in with Google
  Future<bool> signIn() async {
    try {
      _setLoading(true);
      
      if (_googleSignIn == null) {
        await initialize();
      }

      final account = await _googleSignIn?.signIn();
      if (account != null) {
        await _handleSignInSuccess(account);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error signing in: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Handle successful sign in
  Future<void> _handleSignInSuccess(GoogleSignInAccount account) async {
    try {
      _currentUser = account;
      
      // Get authentication headers
      final authHeaders = await account.authHeaders;
      
      // Create auth client for API calls
      _authClient = authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken(
            'Bearer',
            authHeaders['Authorization']?.replaceFirst('Bearer ', '') ?? '',
            DateTime.now().add(const Duration(hours: 1)),
          ),
          null,
          AppConstants.scopes,
        ),
      );

      _isAuthenticated = true;
      
      // Save user info
      await _saveUserInfo(account);
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error handling sign in success: $e');
    }
  }

  /// Save user information to local storage
  Future<void> _saveUserInfo(GoogleSignInAccount account) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final userModel = UserModel(
        id: account.id,
        email: account.email,
        displayName: account.displayName ?? '',
        photoUrl: account.photoUrl,
      );
      
      await prefs.setString(AppConstants.userInfoKey, userModel.toJson());
      await prefs.setString(AppConstants.userTokenKey, 'authenticated');
    } catch (e) {
      debugPrint('Error saving user info: $e');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      _setLoading(true);
      
      await _googleSignIn?.signOut();
      _authClient?.close();
      
      _currentUser = null;
      _authClient = null;
      _isAuthenticated = false;
      
      // Clear stored data
      await _clearStoredData();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error signing out: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Clear stored authentication data
  Future<void> _clearStoredData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.userTokenKey);
      await prefs.remove(AppConstants.userInfoKey);
      await prefs.remove(AppConstants.emailCacheKey);
    } catch (e) {
      debugPrint('Error clearing stored data: $e');
    }
  }

  /// Get fresh authentication headers
  Future<Map<String, String>?> getAuthHeaders() async {
    try {
      if (_currentUser != null) {
        return await _currentUser!.authHeaders;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting auth headers: $e');
      return null;
    }
  }

  /// Check if token is still valid
  Future<bool> isTokenValid() async {
    try {
      final headers = await getAuthHeaders();
      return headers != null && headers.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking token validity: $e');
      return false;
    }
  }

  /// Refresh authentication if needed
  Future<bool> refreshAuthIfNeeded() async {
    try {
      if (!await isTokenValid()) {
        return await signIn();
      }
      return true;
    } catch (e) {
      debugPrint('Error refreshing auth: $e');
      return false;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  @override
  void dispose() {
    _authClient?.close();
    super.dispose();
  }
}