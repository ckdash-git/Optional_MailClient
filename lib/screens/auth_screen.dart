import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_constants.dart';
import '../services/auth_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  final AuthService _authService = AuthService();
  bool _isSigningIn = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: 50.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _animationController.forward();
  }

  Future<void> _handleSignIn() async {
    if (_isSigningIn) return;

    setState(() {
      _isSigningIn = true;
    });

    try {
      final success = await _authService.signIn();
      
      if (success && mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else if (mounted) {
        _showErrorSnackBar('Failed to sign in. Please try again.');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('An error occurred during sign in: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary,
              colorScheme.primary.withOpacity(0.8),
              colorScheme.secondary,
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _slideAnimation.value),
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmallScreen = constraints.maxHeight < 600;
                      final isVerySmallScreen = constraints.maxHeight < 500;
                      
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: constraints.maxWidth > 600 ? 48.0 : 24.0,
                              vertical: isVerySmallScreen ? 16.0 : 24.0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // App Logo and Title
                                _buildHeader(colorScheme, theme, isSmallScreen),
                                
                                SizedBox(
                                  height: isVerySmallScreen 
                                    ? 20 
                                    : isSmallScreen 
                                      ? 30 
                                      : size.height * 0.08,
                                ),
                                
                                // Welcome Text
                                _buildWelcomeText(theme, colorScheme, isSmallScreen),
                                
                                SizedBox(
                                  height: isVerySmallScreen 
                                    ? 16 
                                    : isSmallScreen 
                                      ? 24 
                                      : size.height * 0.06,
                                ),
                                
                                // Features List
                                _buildFeaturesList(theme, colorScheme, isSmallScreen),
                                
                                SizedBox(
                                  height: isVerySmallScreen 
                                    ? 20 
                                    : isSmallScreen 
                                      ? 30 
                                      : size.height * 0.08,
                                ),
                                
                                // Sign In Button
                                _buildSignInButton(theme, colorScheme),
                                
                                const SizedBox(height: 24),
                                
                                // Privacy Notice
                                _buildPrivacyNotice(theme, colorScheme, isSmallScreen),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, ThemeData theme, bool isSmallScreen) {
    final logoSize = isSmallScreen ? 80.0 : 100.0;
    final iconSize = isSmallScreen ? 36.0 : 48.0;
    
    return Column(
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            color: colorScheme.onPrimary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            Icons.smart_toy_rounded,
            size: iconSize,
            color: colorScheme.primary,
          ),
        ),
        SizedBox(height: isSmallScreen ? 16 : 20),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            AppConstants.appName,
            style: theme.textTheme.headlineLarge?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeText(ThemeData theme, ColorScheme colorScheme, bool isSmallScreen) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Welcome to the Future of Email',
            textAlign: TextAlign.center,
            style: (isSmallScreen 
              ? theme.textTheme.titleLarge 
              : theme.textTheme.headlineSmall)?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: isSmallScreen ? 8 : 12),
        Text(
          'Experience AI-powered email management that learns from your habits and organizes your inbox intelligently.',
          textAlign: TextAlign.center,
          style: (isSmallScreen 
            ? theme.textTheme.bodyMedium 
            : theme.textTheme.bodyLarge)?.copyWith(
            color: colorScheme.onPrimary.withOpacity(0.9),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesList(ThemeData theme, ColorScheme colorScheme, bool isSmallScreen) {
    final features = [
      {'icon': Icons.auto_awesome, 'text': 'Smart categorization'},
      {'icon': Icons.security, 'text': 'Secure OAuth authentication'},
      {'icon': Icons.analytics, 'text': 'Email analytics & insights'},
      {'icon': Icons.speed, 'text': 'Lightning-fast performance'},
    ];

    final iconSize = isSmallScreen ? 32.0 : 40.0;
    final iconInnerSize = isSmallScreen ? 16.0 : 20.0;
    final verticalPadding = isSmallScreen ? 6.0 : 8.0;

    return Column(
      children: features.map((feature) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  feature['icon'] as IconData,
                  color: colorScheme.onPrimary,
                  size: iconInnerSize,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  feature['text'] as String,
                  style: (isSmallScreen 
                    ? theme.textTheme.bodyMedium 
                    : theme.textTheme.bodyLarge)?.copyWith(
                    color: colorScheme.onPrimary.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSignInButton(ThemeData theme, ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isSigningIn ? null : _handleSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.onPrimary,
          foregroundColor: colorScheme.primary,
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isSigningIn
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/images/google_logo.svg',
                    width: 24,
                    height: 24,
                    placeholderBuilder: (context) => Icon(
                      Icons.login,
                      size: 24,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPrivacyNotice(ThemeData theme, ColorScheme colorScheme, bool isSmallScreen) {
    return Text(
      'By continuing, you agree to our Terms of Service and Privacy Policy. Your data is encrypted and secure.',
      textAlign: TextAlign.center,
      style: (isSmallScreen 
        ? theme.textTheme.bodySmall?.copyWith(fontSize: 11) 
        : theme.textTheme.bodySmall)?.copyWith(
        color: colorScheme.onPrimary.withOpacity(0.7),
        height: 1.4,
      ),
    );
  }
}