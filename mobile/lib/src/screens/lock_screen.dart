import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../data/local_vault.dart';
import '../data/auth_service.dart';
import '../widgets/pattern_lock_view.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.vault, required this.onUnlock});

  final LocalVault vault;
  final void Function(bool isHiddenVault) onUnlock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _authService = AuthService();
  final _localAuth = LocalAuthentication();

  AuthLockType _currentType = AuthLockType.pin;
  String _enteredPin = '';
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  int _secretTapCount = 0;
  DateTime? _lastTapTime;
  bool _busy = false;
  bool _unlockCelebration = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreferredLock();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferredLock() async {
    final type = await _authService.getPreferredLockType();
    setState(() => _currentType = type);
    if (type == AuthLockType.biometric) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _authenticateBiometric(),
      );
    }
  }

  Future<void> _authenticateBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final canCheck =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canCheck) {
        setState(() {
          _error =
              'Biometrics not available on this device. Use PIN or Password.';
          _currentType = AuthLockType.pin;
        });
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock your Keepsake Vault',
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        await widget.vault.initialize();
        if (!mounted) return;
        setState(() => _unlockCelebration = true);
        await Future<void>.delayed(const Duration(milliseconds: 850));
        if (mounted) widget.onUnlock(false);
      } else {
        setState(() => _error = 'Authentication cancelled.');
      }
    } catch (e) {
      setState(() => _error = 'Biometric check failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPinKey(String char) {
    if (_enteredPin.length >= 6) return;
    setState(() {
      _enteredPin += char;
      _error = null;
    });

    if (_enteredPin.length >= 4) {
      _checkPin(_enteredPin);
    }
  }

  void _onPinBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _error = null;
      });
    }
  }

  Future<void> _checkPin(String pin) async {
    final hiddenPin = await _authService.getHiddenVaultPin();
    final isHiddenEnabled = await _authService.isHiddenVaultEnabled();

    // Check hidden vault first (Decoy PIN)
    if (isHiddenEnabled && pin == hiddenPin) {
      await widget.vault.initialize();
      widget.onUnlock(true); // Open Hidden Vault!
      return;
    }

    final realPin = await _authService.getPin();
    if (pin == realPin || (realPin == null && pin == '1234')) {
      await widget.vault.initialize();
      widget.onUnlock(false); // Open Normal Vault
      return;
    }

    if (pin.length >= 4 && realPin != null && realPin.length == pin.length) {
      setState(() {
        _error = 'Incorrect PIN code.';
        _enteredPin = '';
      });
    }
  }

  Future<void> _checkPattern(String pattern) async {
    final savedPattern = await _authService.getPattern();
    if (savedPattern == null || pattern == savedPattern) {
      await widget.vault.initialize();
      widget.onUnlock(false);
    } else {
      setState(() => _error = 'Incorrect pattern. Try again.');
    }
  }

  Future<void> _checkPassword() async {
    final text = _passwordController.text;
    if (text.isEmpty) return;

    final saved = await _authService.getPassword();
    if (saved == text) {
      await widget.vault.initialize();
      widget.onUnlock(false);
    } else {
      setState(() => _error = 'Incorrect Master Password.');
    }
  }

  void _onLogoTap() {
    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!).inSeconds > 2) {
      _secretTapCount = 1;
    } else {
      _secretTapCount++;
    }
    _lastTapTime = now;

    if (_secretTapCount >= 3) {
      _secretTapCount = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🕵️ Decoy / Hidden Safe mode activated. Enter decoy PIN or passcode.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Secret Tap Logo
                      GestureDetector(
                        onTap: _onLogoTap,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              border: Border.all(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.3,
                                ),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.lock_rounded,
                              size: 44,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Vault Locked',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Authenticate to access your encrypted records',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Mode Selector Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildModeIcon(
                            Icons.dialpad,
                            AuthLockType.pin,
                            'PIN',
                          ),
                          const SizedBox(width: 12),
                          _buildModeIcon(
                            Icons.gesture,
                            AuthLockType.pattern,
                            'Pattern',
                          ),
                          const SizedBox(width: 12),
                          _buildModeIcon(
                            Icons.fingerprint,
                            AuthLockType.biometric,
                            'Biometrics',
                          ),
                          const SizedBox(width: 12),
                          _buildModeIcon(
                            Icons.password,
                            AuthLockType.password,
                            'Password',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Unlock Body depending on mode
                      _buildLockBody(theme),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_unlockCelebration)
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.surface,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.72, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 520),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) => Opacity(
                      opacity: scale.clamp(0, 1),
                      child: Transform.scale(scale: scale, child: child),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primaryContainer,
                          ),
                          child: Icon(
                            Icons.verified_rounded,
                            size: 58,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Vault unlocked',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your private library is ready.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeIcon(IconData icon, AuthLockType type, String tooltip) {
    final isSelected = _currentType == type;
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            _currentType = type;
            _error = null;
          });
          if (type == AuthLockType.biometric) {
            _authenticateBiometric();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : Theme.of(context).dividerColor.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildLockBody(ThemeData theme) {
    switch (_currentType) {
      case AuthLockType.pin:
        return _buildPinKeypad(theme);
      case AuthLockType.pattern:
        return _buildPatternBody(theme);
      case AuthLockType.biometric:
        return _buildBiometricBody(theme);
      case AuthLockType.password:
        return _buildPasswordBody(theme);
    }
  }

  Widget _buildPinKeypad(ThemeData theme) {
    return Column(
      children: [
        // Dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            final filled = index < _enteredPin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? theme.colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: filled ? theme.colorScheme.primary : theme.hintColor,
                  width: 2,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 28),

        // 3x4 Keypad
        for (var row = 0; row < 3; row++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var col = 1; col <= 3; col++)
                _buildKeyButton((row * 3 + col).toString()),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() => _enteredPin = ''),
            ),
            _buildKeyButton('0'),
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.backspace_outlined),
              onPressed: _onPinBackspace,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyButton(String text) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _onPinKey(text),
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.cardTheme.color ?? theme.colorScheme.surface,
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPatternBody(ThemeData theme) {
    return Column(
      children: [
        const Text(
          'Draw your secret pattern to unlock',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        Center(
          child: PatternLockView(dimension: 260, onComplete: _checkPattern),
        ),
      ],
    );
  }

  Widget _buildBiometricBody(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Icon(Icons.fingerprint, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          _busy
              ? 'Scanning biometrics…'
              : 'Touch fingerprint sensor or face camera',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _authenticateBiometric,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Biometrics Again'),
        ),
      ],
    );
  }

  Widget _buildPasswordBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          onSubmitted: (_) => _checkPassword(),
          decoration: InputDecoration(
            labelText: 'Master Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _checkPassword,
          icon: const Icon(Icons.lock_open),
          label: const Text('Unlock with Password'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
