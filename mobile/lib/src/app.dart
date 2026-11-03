import 'package:flutter/material.dart';

import 'dart:async';

import 'data/local_vault.dart';
import 'data/auth_service.dart';
import 'models/theme_settings.dart';
import 'screens/auth_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/main_dashboard.dart';
import 'widgets/keepsake_logo.dart';

class KeepsakeApp extends StatelessWidget {
  const KeepsakeApp({super.key, required this.vault});
  final LocalVault vault;

  @override
  Widget build(BuildContext context) {
    final themeCtrl = AppThemeController.instance;

    return ListenableBuilder(
      listenable: themeCtrl,
      builder: (context, _) => MaterialApp(
        title: 'Keep Safe',
        debugShowCheckedModeBanner: false,
        theme: themeCtrl.themeData,
        home: AppRootFlow(vault: vault),
      ),
    );
  }
}

enum _FlowState { loading, auth, locked, unlocked }

class AppRootFlow extends StatefulWidget {
  const AppRootFlow({super.key, required this.vault});
  final LocalVault vault;

  @override
  State<AppRootFlow> createState() => _AppRootFlowState();
}

class _AppRootFlowState extends State<AppRootFlow> with WidgetsBindingObserver {
  final _authService = AuthService();
  _FlowState _state = _FlowState.loading;
  bool _isHiddenVault = false;
  DateTime? _backgroundedAt;
  Timer? _autoLockTimer;
  bool _isInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoLockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isInBackground = true;
      _scheduleAutoLock();
    } else if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      _autoLockTimer?.cancel();
      _autoLockTimer = null;
      final elapsed = _backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      _lockIfExpired(elapsed);
    }
  }

  Future<void> _scheduleAutoLock() async {
    if (_state != _FlowState.unlocked || _backgroundedAt != null) return;
    _backgroundedAt = DateTime.now();
    final timeoutMinutes = await _authService.getAutoLockMinutes();
    if (!mounted || !_isInBackground || _state != _FlowState.unlocked) return;
    if (timeoutMinutes == 0) {
      setState(() => _state = _FlowState.locked);
      return;
    }
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(Duration(minutes: timeoutMinutes), () {
      if (mounted && _state == _FlowState.unlocked) {
        setState(() => _state = _FlowState.locked);
      }
    });
  }

  void _lockIfExpired(Duration elapsed) {
    if (_state != _FlowState.unlocked) return;
    _authService.getAutoLockMinutes().then((timeout) {
      if (mounted &&
          _state == _FlowState.unlocked &&
          (timeout == 0 || elapsed >= Duration(minutes: timeout))) {
        setState(() => _state = _FlowState.locked);
      }
    });
  }

  Future<void> _checkInitialState() async {
    final isRegistered = await _authService.isRegistered();
    if (mounted) {
      setState(() {
        _state = isRegistered ? _FlowState.locked : _FlowState.auth;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _FlowState.loading:
        return const _LaunchScreen();

      case _FlowState.auth:
        return AuthScreen(
          vault: widget.vault,
          onAuthSuccess: () {
            setState(() {
              _state = _FlowState.unlocked;
              _isHiddenVault = false;
            });
          },
        );

      case _FlowState.locked:
        return LockScreen(
          vault: widget.vault,
          onUnlock: (isHidden) {
            setState(() {
              _isHiddenVault = isHidden;
              _state = _FlowState.unlocked;
            });
          },
        );

      case _FlowState.unlocked:
        return MainDashboard(
          vault: widget.vault,
          isHiddenVault: _isHiddenVault,
          onLock: () {
            setState(() {
              _state = _FlowState.locked;
            });
          },
          onLogout: () {
            setState(() {
              _state = _FlowState.auth;
            });
          },
        );
    }
  }
}

class _LaunchScreen extends StatefulWidget {
  const _LaunchScreen();

  @override
  State<_LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<_LaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(
                CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
              ),
              child: const KeepsakeLogo(size: 84),
            ),
            const SizedBox(height: 22),
            Text(
              'Keep Safe',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
