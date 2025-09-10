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
              horizontal: constraints.maxWidth * (constraints.maxWidth > 600 ? 0.08 : 0.06),
              vertical: size.height * (isVerySmallScreen ? 0.02 : 0.03),
            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // App Logo and Title
                                _buildHeader(colorScheme, theme, isSmallScreen),
                                
                                SizedBox(
                                  height: size.height * (isVerySmallScreen 
                                    ? 0.05 
                                    : isSmallScreen 
                                      ? 0.08 
                                      : 0.12),
                                ),
                                
                                // Welcome Text
                                _buildWelcomeText(theme, colorScheme, isSmallScreen),
                                
                                SizedBox(
                                  height: size.height * (isVerySmallScreen 
                                    ? 0.05 
                                    : isSmallScreen 
                                      ? 0.08 
                                      : 0.12),
                                ),
                                
                                // Sign In Button
                                _buildSignInButton(theme, colorScheme),
                                
                                SizedBox(height: size.height * 0.04),
                                
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
    final size = MediaQuery.of(context).size;
    final logoSize = size.width * (isSmallScreen ? 0.25 : 0.3);
    final iconSize = size.width * (isSmallScreen ? 0.12 : 0.15);
    
    return Column(
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            color: colorScheme.onPrimary,
            borderRadius: BorderRadius.circular(size.width * 0.06),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.mail_outline_rounded,
            size: iconSize,
            color: colorScheme.primary,
          ),
        ),
        SizedBox(height: size.height * (isSmallScreen ? 0.025 : 0.03)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            AppConstants.appName,
            style: theme.textTheme.headlineLarge?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontSize: size.width * (isSmallScreen ? 0.07 : 0.08),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeText(ThemeData theme, ColorScheme colorScheme, bool isSmallScreen) {
    final size = MediaQuery.of(context).size;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Simplify Your Email Experience',
            textAlign: TextAlign.center,
            style: (isSmallScreen 
              ? theme.textTheme.titleLarge 
              : theme.textTheme.headlineSmall)?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
              fontSize: size.width * (isSmallScreen ? 0.055 : 0.065),
            ),
          ),
        ),
        SizedBox(height: size.height * (isSmallScreen ? 0.015 : 0.02)),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: size.width * (isSmallScreen ? 0.04 : 0.08),
          ),
          child: Text(
            'Access and manage your Gmail with a clean, intuitive interface designed for productivity.',
            textAlign: TextAlign.center,
            style: (isSmallScreen 
              ? theme.textTheme.bodyMedium 
              : theme.textTheme.bodyLarge)?.copyWith(
              color: colorScheme.onPrimary.withOpacity(0.85),
              height: 1.6,
              fontSize: size.width * (isSmallScreen ? 0.035 : 0.04),
            ),
          ),
        ),
      ],
    );
  }



  Widget _buildSignInButton(ThemeData theme, ColorScheme colorScheme) {
    final size = MediaQuery.of(context).size;
    return Container(
      width: double.infinity,
      height: size.height * 0.08,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size.width * 0.05),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSigningIn ? null : _handleSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.onPrimary,
          foregroundColor: colorScheme.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(size.width * 0.05),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: size.width * 0.06, 
            vertical: size.height * 0.02
          ),
        ),
        child: _isSigningIn
            ? SizedBox(
                width: size.width * 0.07,
                height: size.width * 0.07,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
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
                    width: size.width * 0.07,
                    height: size.width * 0.07,
                    placeholderBuilder: (context) => Icon(
                      Icons.login_rounded,
                      size: size.width * 0.07,
                      color: colorScheme.primary,
                    ),
                  ),
                  SizedBox(width: size.width * 0.04),
                  Text(
                    'Continue with Google',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: size.width * 0.045,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPrivacyNotice(ThemeData theme, ColorScheme colorScheme, bool isSmallScreen) {
    final size = MediaQuery.of(context).size;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * (isSmallScreen ? 0.06 : 0.12),
      ),
      child: Text(
        'Secure authentication via Google. Your privacy is protected.',
        textAlign: TextAlign.center,
        style: (isSmallScreen 
          ? theme.textTheme.bodySmall?.copyWith(fontSize: size.width * 0.03) 
          : theme.textTheme.bodySmall)?.copyWith(
          color: colorScheme.onPrimary.withOpacity(0.75),
          height: 1.5,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}