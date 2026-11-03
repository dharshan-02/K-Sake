import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/auth_service.dart';
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
  static const _demoEmail = 'demo@keepsake.local';
  static const _demoPassword = 'KeepsakeDemo!2026';

  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  final _authService = AuthService();
  late final ApiClient _apiClient = ApiClient(widget.vault);

  final _signInEmail = TextEditingController();
  final _signInPassword = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _showPassword = false;
  bool _deviceOnly = false;
  bool _busy = false;
  String? _error;

  bool get _isSignIn => _tabController.index == 0;

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
    if (kDebugMode && email == _demoEmail && password == _demoPassword) {
      await _openDemoVault();
      return;
    }
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

      if (_deviceOnly) {
        throw StateError(
          'There is no matching account saved on this device. Connect to your account or create a device-only vault.',
        );
      }

      await _apiClient.authenticate(email, password, createAccount: false);
      await widget.vault.setMasterKeyFromCredentials(email, password);
      await _authService.registerUser(
        email: email,
        password: password,
        lockType: AuthLockType.password,
        cloudAccount: !_deviceOnly,
      );
      widget.onAuthSuccess();
    } catch (error) {
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
    if (password.length < 12) {
      setState(() => _error = 'Use at least 12 characters for your password.');
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
      if (!_deviceOnly) {
        await _apiClient.authenticate(email, password, createAccount: true);
      }

      await widget.vault.setMasterKeyFromCredentials(email, password);
      // A new account starts with its master password as the local unlock
      // method. Users can choose biometrics, a PIN, or a pattern in Settings.
      await _authService.registerUser(
        email: email,
        password: password,
        lockType: AuthLockType.password,
        cloudAccount: !_deviceOnly,
      );
      widget.onAuthSuccess();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDemoVault() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existingEmail = await _authService.getUserEmail();
      if (await _authService.isRegistered() &&
          existingEmail?.toLowerCase() != _demoEmail) {
        throw StateError(
          'A different local account is already set up on this device. Sign in to it to keep its vault data.',
        );
      }

      await widget.vault.setMasterKeyFromCredentials(_demoEmail, _demoPassword);
      await _authService.registerUser(
        email: _demoEmail,
        password: _demoPassword,
        lockType: AuthLockType.password,
        cloudAccount: false,
      );
      widget.onAuthSuccess();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is ApiConnectionException) return error.message;
    if (error is TimeoutException || error is SocketException) {
      return 'Keepsake could not reach the server. Check your connection and API address, or use a local account on this device.';
    }
    if (error is FormatException) {
      return 'The server response was invalid. Check that the Keepsake API is running the expected version.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _configureServerUrl() async {
    final controller = TextEditingController(
      text: await ApiClient.getBaseUrl(),
    );
    if (!mounted) return;
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cloud sign-in needs the Keepsake API and database to be running. 10.0.2.2 only works in the Android emulator. On a physical phone, enter your computer’s Wi-Fi address, for example http://192.168.1.20:3000/v1. Keep both devices on the same Wi-Fi and use HTTPS for a public server.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'API base URL',
                hintText: 'http://10.0.2.2:3000/v1',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'HTTP is for local development only. Use HTTPS for a deployed server.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null || updated.isEmpty) return;
    try {
      final uri = Uri.parse(updated);
      if (!uri.hasScheme || uri.host.isEmpty) {
        throw const FormatException('Enter a complete server URL.');
      }
      await ApiClient.setBaseUrl(updated);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Server address saved.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
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
                colors.primary.withValues(alpha: 0.045),
                colors.surface,
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: KeepsakeLogo(size: 46, showWordmark: true),
                          ),
                          IconButton(
                            tooltip: 'Server address',
                            onPressed: _configureServerUrl,
                            icon: const Icon(Icons.tune_rounded),
                          ),
                        ],
                      ),
                      SizedBox(height: constraints.maxHeight < 720 ? 14 : 28),
                      Text(
                        _isSignIn
                            ? 'Your files,\nwithin reach.'
                            : 'A calmer place\nfor your files.',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.06,
                          letterSpacing: -1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isSignIn
                            ? 'Sign in to your private vault. Your local files stay available offline.'
                            : 'Create your private vault. You can choose biometrics or another unlock method later in Settings.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildAuthPanel(theme),
                      if (kDebugMode && _isSignIn) ...[
                        const SizedBox(height: 14),
                        _buildDemoCard(theme),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 15,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'Encrypted on this device · Works offline',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.045),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(15),
            ),
            child: TabBar(
              controller: _tabController,
              onTap: (_) => setState(() => _error = null),
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.07),
                    blurRadius: 7,
                  ),
                ],
              ),
              labelColor: colors.primary,
              unselectedLabelColor: colors.onSurfaceVariant,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Sign in'),
                Tab(text: 'Create account'),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colors.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        height: 1.35,
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
              duration: const Duration(milliseconds: 220),
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
      const SizedBox(height: 9),
      _deviceOnlySwitch(
        theme,
        copy: 'Use saved local account',
        subtitle: 'Do not contact the cloud server for sign-in',
      ),
      const SizedBox(height: 14),
      _submitButton(
        label: 'Sign in to vault',
        icon: Icons.arrow_forward_rounded,
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
      _passwordInput(_registerPassword, label: 'Create password'),
      const SizedBox(height: 14),
      _passwordInput(_confirmPassword, label: 'Confirm password'),
      const SizedBox(height: 9),
      _accountTypeChoice(theme),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.fingerprint_rounded,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _deviceOnly
                    ? 'Device-only vault: your sign-in stays on this device and no cloud account is created. You can choose an unlock method later in Settings.'
                    : 'Cloud account: files stay on this device first and upload encrypted when you sync. You can choose an unlock method later in Settings.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 15),
      _submitButton(
        label: 'Create private vault',
        icon: Icons.shield_outlined,
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
      prefixIcon: Icon(icon),
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
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
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        tooltip: _showPassword ? 'Hide password' : 'Show password',
        onPressed: () => setState(() => _showPassword = !_showPassword),
        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
      ),
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    ),
  );

  Widget _deviceOnlySwitch(
    ThemeData theme, {
    required String copy,
    required String subtitle,
  }) => Material(
    color: Colors.transparent,
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        copy,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      value: _deviceOnly,
      onChanged: _busy ? null : (value) => setState(() => _deviceOnly = value),
    ),
  );

  Widget _accountTypeChoice(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Where should your vault live?',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            avatar: const Icon(Icons.cloud_outlined, size: 18),
            label: const Text('Cloud account'),
            selected: !_deviceOnly,
            onSelected: _busy
                ? null
                : (_) => setState(() => _deviceOnly = false),
          ),
          ChoiceChip(
            avatar: const Icon(Icons.phone_android_rounded, size: 18),
            label: const Text('Device only'),
            selected: _deviceOnly,
            onSelected: _busy
                ? null
                : (_) => setState(() => _deviceOnly = true),
          ),
        ],
      ),
    ],
  );

  Widget _submitButton({
    required String label,
    required IconData icon,
    required Future<void> Function() onPressed,
  }) => SizedBox(
    height: 54,
    child: FilledButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: _busy
          ? const SizedBox.square(
              dimension: 19,
              child: CircularProgressIndicator(strokeWidth: 2.3),
            )
          : Icon(icon),
      label: Text(_busy ? 'Please wait…' : label),
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );

  Widget _buildDemoCard(ThemeData theme) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: theme.colorScheme.secondary.withValues(alpha: 0.22),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.science_outlined, color: theme.colorScheme.secondary),
            Text(
              'Demo access',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Chip(label: Text('DEBUG')),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Local sample account · does not contact a server',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SelectableText('Email  $_demoEmail'),
        const SizedBox(height: 3),
        SelectableText('Password  $_demoPassword'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openDemoVault,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Open demo vault'),
        ),
      ],
    ),
  );
}
