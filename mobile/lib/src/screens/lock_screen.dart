import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../data/local_vault.dart';
import '../data/auth_service.dart';
import '../widgets/keepsake_logo.dart';
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

  AuthLockType _currentType = AuthLockType.password;
  String _enteredPin = '';
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  int _secretTapCount = 0;
  DateTime? _lastTapTime;
  bool _busy = false;
  bool _unlockCelebration = false;
  bool _hiddenEntryMode = false;
  int _hiddenPinLength = 4;
  int _regularPinLength = 4;
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
    final hiddenPin = await _authService.getHiddenVaultPin();
    final regularPin = await _authService.getPin();
    if (!mounted) return;
    setState(() {
      _currentType = type;
      _hiddenPinLength = hiddenPin.length < 4
          ? 4
          : hiddenPin.length.clamp(4, 6);
      _regularPinLength = regularPin == null
          ? 4
          : regularPin.length.clamp(4, 6);
    });
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
        localizedReason: 'Authenticate to unlock your Keep Safe Vault',
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        await widget.vault.initialize();
        if (!mounted) return;
        setState(() => _unlockCelebration = true);
        await Future<void>.delayed(const Duration(milliseconds: 850));
        if (mounted) widget.onUnlock(false);
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (!errStr.contains('usercanceled') &&
          !errStr.contains('cancel') &&
          !errStr.contains('authinprogress') &&
          !errStr.contains('notavailable')) {
        setState(() => _error = 'Biometrics check did not complete. Try again or switch method.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPinKey(String char) {
    final maxLength = _pinEntryLength;
    if (_enteredPin.length >= maxLength) return;
    setState(() {
      _enteredPin += char;
      _error = null;
    });
  }

  int get _pinEntryLength =>
      _hiddenEntryMode ? _hiddenPinLength : _regularPinLength;

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

    if (_hiddenEntryMode) {
      if (isHiddenEnabled && hiddenPin.isNotEmpty && pin == hiddenPin) {
        await widget.vault.initialize();
        if (mounted) widget.onUnlock(true);
      } else if (pin.length >= 4 && mounted) {
        setState(() {
          _error = 'That Hidden Safe PIN is not correct.';
          _enteredPin = '';
        });
      }
      return;
    }

    // The Hidden Safe PIN also acts as an alternate PIN unlock when enabled.
    if (isHiddenEnabled && pin == hiddenPin) {
      await widget.vault.initialize();
      widget.onUnlock(true); // Open Hidden Vault!
      return;
    }

    final realPin = await _authService.getPin();
    if (realPin != null && pin == realPin) {
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
    if (savedPattern != null && pattern == savedPattern) {
      await widget.vault.initialize();
      widget.onUnlock(false);
    } else {
      if (mounted) {
        setState(
          () => _error = savedPattern == null
              ? 'No pattern is configured. Choose your saved unlock method in Settings.'
              : 'Incorrect pattern. Try again.',
        );
      }
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

  Future<void> _onLogoTap() async {
    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!).inSeconds > 2) {
      _secretTapCount = 1;
    } else {
      _secretTapCount++;
    }
    _lastTapTime = now;

    if (_secretTapCount >= 3) {
      _secretTapCount = 0;
      final enabled = await _authService.isHiddenVaultEnabled();
      if (!mounted) return;
      final hiddenPin = await _authService.getHiddenVaultPin();
      if (!mounted) return;
      if (!enabled || hiddenPin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Set up a Hidden Safe PIN in Settings first.'),
          ),
        );
        return;
      }
      setState(() {
        _hiddenEntryMode = true;
        _enteredPin = '';
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your Hidden Safe PIN.'),
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
                        child: Center(child: const KeepsakeLogo(size: 80)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _hiddenEntryMode ? 'Hidden Safe' : 'Vault Locked',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _hiddenEntryMode
                            ? 'Enter your separate Hidden Safe PIN'
                            : 'Authenticate to access your encrypted records',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(height: 20),

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
                      if (_hiddenEntryMode) ...[
                        _buildPinKeypad(theme),
                        TextButton(
                          onPressed: () => setState(() {
                            _hiddenEntryMode = false;
                            _enteredPin = '';
                            _error = null;
                          }),
                          child: const Text('Back to regular unlock'),
                        ),
                      ] else
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
    final pinLength = _pinEntryLength;
    return Column(
      children: [
        // Dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pinLength, (index) {
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
              tooltip: 'Delete last digit',
              icon: const Icon(Icons.backspace_outlined),
              onPressed: _onPinBackspace,
            ),
            _buildKeyButton('0'),
            SizedBox(
              width: 88,
              height: 48,
              child: FilledButton.icon(
                onPressed: _enteredPin.length == pinLength
                    ? () => _checkPin(_enteredPin)
                    : null,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Enter'),
              ),
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
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _error = null;
            _currentType = AuthLockType.pin;
          }),
          child: const Text('Unlock with PIN or Password'),
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
