import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/firebase_sync_service.dart';
import '../data/local_vault.dart';
import '../widgets/keepsake_logo.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.vault,
    required this.onAuthSuccess,
  });

  final LocalVault vault;
  final VoidCallback onAuthSuccess;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  final _authService = AuthService();
  late final FirebaseSyncService _firebaseSync = FirebaseSyncService(widget.vault);

  final _signInEmail = TextEditingController();
  final _signInPassword = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  bool get _isSignIn => _tabController.index == 0;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      if (mounted) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _signInEmail.dispose();
    _signInPassword.dispose();
    _registerEmail.dispose();
    _registerPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _signInEmail.text.trim().toLowerCase();
    final password = _signInPassword.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password to continue.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final savedEmail = (await _authService.getUserEmail())?.toLowerCase();
      final savedPassword = await _authService.getPassword();
      if (savedEmail == email && savedPassword == password) {
        await widget.vault.setMasterKeyFromCredentials(email, password);
        widget.onAuthSuccess();
        return;
      }

      // Firebase Authentication
      await _firebaseSync.signIn(email, password);

      await widget.vault.setMasterKeyFromCredentials(email, password);
      await _authService.registerUser(
        email: email,
        password: password,
        lockType: AuthLockType.password,
        cloudAccount: true,
      );
      widget.onAuthSuccess();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final cred = await _firebaseSync.signInWithGoogle();
      final user = cred.user;
      if (user != null) {
        final email = (user.email ?? 'google_user@keepsake.local').toLowerCase();
        final password = user.uid;
        await widget.vault.setMasterKeyFromCredentials(email, password);
        await _authService.registerUser(
          email: email,
          password: password,
          lockType: AuthLockType.password,
          cloudAccount: true,
        );
        widget.onAuthSuccess();
      }
    } catch (error) {
      final msg = error.toString();
      if (msg.contains('cancelled') || msg.contains('canceled')) {
        return;
      }
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleRegister() async {
    final email = _registerEmail.text.trim().toLowerCase();
    final password = _registerPassword.text;
    final confirmation = _confirmPassword.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Use at least 8 characters for your master password.');
      return;
    }
    if (password != confirmation) {
      setState(() => _error = 'Those passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Firebase Account Creation
      await _firebaseSync.signUp(email, password);

      await widget.vault.setMasterKeyFromCredentials(email, password);
      await _authService.registerUser(
        email: email,
        password: password,
        lockType: AuthLockType.password,
        cloudAccount: true,
      );
      widget.onAuthSuccess();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _signInEmail.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email in the field above to receive a reset link.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _firebaseSync.sendPasswordReset(email);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Password Reset Sent'),
            content: Text(
              'A reset link has been dispatched to $email. Follow the link to change your password.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found with this email. Tap "Create account" to register.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password. Please check and try again.';
        case 'email-already-in-use':
          return 'An account already exists with this email. Please switch to "Sign in".';
        case 'weak-password':
          return 'Password is too weak. Please use at least 6 characters.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'network-request-failed':
          return 'Network error. Check your internet connection.';
        case 'account-exists-with-different-credential':
          return 'An account already exists with this email under a different sign-in method.';
        default:
          return error.message ?? 'Authentication failed.';
      }
    }
    final str = error.toString();
    if (str.contains('sign_in_failed') || str.contains('10') || str.contains('12500')) {
      return 'Google Sign-In failed. Please sign in with email and password.';
    }
    if (error is TimeoutException || error is SocketException) {
      return 'Network timeout. Please check your internet connection.';
    }
    return str.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.surface,
              Color.alphaBlend(
                colors.primary.withValues(alpha: 0.04),
                colors.surface,
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: KeepsakeLogo(size: 60, showWordmark: true),
                      ),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Column(
                          key: ValueKey(_isSignIn),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isSignIn
                                  ? 'Your files,\nwithin reach.'
                                  : 'A calmer place\nfor your files.',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                letterSpacing: -1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _isSignIn
                                  ? 'Sign in to access your encrypted vault. Files stay securely available offline.'
                                  : 'Create your private vault. Unlock with biometrics, pin, or password anytime.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildAuthPanel(theme),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 15,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Encrypted on this device · Zero-knowledge privacy',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthPanel(ThemeData theme) {
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              onTap: (_) => setState(() => _error = null),
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: colors.primary,
              unselectedLabelColor: colors.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Sign in'),
                Tab(text: 'Create account'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildGoogleButton(theme),
          _buildOrDivider(theme),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.error.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: colors.error,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _tabController.index == 0
                  ? _buildSignInForm(theme)
                  : _buildRegisterForm(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleButton(ThemeData theme) {
    final colors = theme.colorScheme;
    return OutlinedButton(
      onPressed: _busy ? null : _handleGoogleSignIn,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        side: BorderSide(color: colors.outlineVariant),
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(20, 20),
            painter: _GoogleLogoPainter(),
          ),
          const SizedBox(width: 12),
          Text(
            _isSignIn ? 'Continue with Google' : 'Sign up with Google',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrDivider(ThemeData theme) {
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: colors.outlineVariant.withValues(alpha: 0.6),
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'or continue with email',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: colors.outlineVariant.withValues(alpha: 0.6),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInForm(ThemeData theme) => Column(
    key: const ValueKey('sign-in-form'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _input(
        controller: _signInEmail,
        label: 'Email address',
        icon: Icons.alternate_email_rounded,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 14),
      _passwordInput(_signInPassword, label: 'Password'),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _busy ? null : _handleForgotPassword,
          child: Text(
            'Forgot password?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      _submitButton(
        label: 'Sign in to vault',
        icon: Icons.lock_open_rounded,
        onPressed: _handleSignIn,
      ),
    ],
  );

  Widget _buildRegisterForm(ThemeData theme) => Column(
    key: const ValueKey('register-form'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _input(
        controller: _registerEmail,
        label: 'Email address',
        icon: Icons.alternate_email_rounded,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 14),
      _passwordInput(_registerPassword, label: 'Create master password'),
      const SizedBox(height: 14),
      _passwordInput(_confirmPassword, label: 'Confirm password'),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 15,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'Zero-knowledge AES-256 encrypted',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _submitButton(
        label: 'Create secure vault',
        icon: Icons.lock_rounded,
        onPressed: _handleRegister,
      ),
    ],
  );

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
  }) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );

  Widget _passwordInput(
    TextEditingController controller, {
    required String label,
  }) => TextField(
    controller: controller,
    obscureText: !_showPassword,
    textInputAction: TextInputAction.next,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
      suffixIcon: IconButton(
        tooltip: _showPassword ? 'Hide password' : 'Show password',
        onPressed: () => setState(() => _showPassword = !_showPassword),
        icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
      ),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );

  Widget _submitButton({
    required String label,
    required IconData icon,
    required Future<void> Function() onPressed,
  }) => SizedBox(
    height: 52,
    child: FilledButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: _busy
          ? const SizedBox.square(
              dimension: 19,
              child: CircularProgressIndicator(strokeWidth: 2.3, color: Colors.white),
            )
          : Icon(icon, size: 19),
      label: Text(_busy ? 'Please wait…' : label),
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 1,
      ),
    ),
  );
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double stroke = w * 0.22;
    final center = Offset(w / 2, h / 2);
    final radius = (w - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Red arc (top)
    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -3.14159 * 0.72, 3.14159 * 0.52, false, redPaint);

    // Yellow arc (bottom-left)
    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 3.14159 * 0.65, 3.14159 * 0.55, false, yellowPaint);

    // Green arc (bottom)
    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 3.14159 * 0.08, 3.14159 * 0.57, false, greenPaint);

    // Blue arc (right)
    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -3.14159 * 0.2, 3.14159 * 0.28, false, bluePaint);

    // Blue horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final barRect = Rect.fromLTRB(
      center.dx - stroke * 0.1,
      center.dy - stroke / 2,
      center.dx + radius + stroke / 2,
      center.dy + stroke / 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, Radius.circular(stroke * 0.2)),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
