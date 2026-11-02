import 'package:flutter/material.dart';
import 'data/local_vault.dart';
import 'data/auth_service.dart';
import 'models/theme_settings.dart';
import 'screens/auth_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/main_dashboard.dart';

class KeepsakeApp extends StatelessWidget {
  const KeepsakeApp({super.key, required this.vault});
  final LocalVault vault;

  @override
  Widget build(BuildContext context) {
    final themeCtrl = AppThemeController.instance;

    return ListenableBuilder(
      listenable: themeCtrl,
      builder: (context, _) => MaterialApp(
        title: 'Keepsake',
        debugShowCheckedModeBanner: false,
        theme: themeCtrl.themeData,
        home: AppRootFlow(vault: vault),
      ),
    );
  }
}

enum _FlowState {
  loading,
  auth,
  locked,
  unlocked,
}

class AppRootFlow extends StatefulWidget {
  const AppRootFlow({super.key, required this.vault});
  final LocalVault vault;

  @override
  State<AppRootFlow> createState() => _AppRootFlowState();
}

class _AppRootFlowState extends State<AppRootFlow> {
  final _authService = AuthService();
  _FlowState _state = _FlowState.loading;
  bool _isHiddenVault = false;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
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
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );

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
        );
    }
  }
}
