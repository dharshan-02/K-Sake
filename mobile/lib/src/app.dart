import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'data/local_vault.dart';
import 'screens/vault_screen.dart';

class KeepsakeApp extends StatelessWidget {
  const KeepsakeApp({super.key, required this.vault});
  final LocalVault vault;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Keepsake',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF315C54),
            surface: const Color(0xFFF7F8F5),
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F8F5),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F8F5)),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        home: UnlockGate(vault: vault),
      );
}

class UnlockGate extends StatefulWidget {
  const UnlockGate({super.key, required this.vault});
  final LocalVault vault;

  @override
  State<UnlockGate> createState() => _UnlockGateState();
}

class _UnlockGateState extends State<UnlockGate> {
  bool _busy = false;
  bool _unlocked = false;
  String? _error;
  final _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final supported = await _auth.isDeviceSupported();
      final authenticated = supported && await _auth.authenticate(
        localizedReason: 'Unlock your private file vault',
        persistAcrossBackgrounding: true,
      );
      if (!authenticated) throw StateError('Authentication was not completed.');
      await widget.vault.initialize();
      if (mounted) setState(() => _unlocked = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Authenticate with your device to open Keepsake.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return VaultScreen(vault: widget.vault);
    return Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.shield_moon_outlined, size: 56),
        const SizedBox(height: 20),
        Text('Your files, kept private', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Unlock with your device biometrics or passcode.'),
        if (_error != null) ...[const SizedBox(height: 16), Text(_error!, textAlign: TextAlign.center)],
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: _busy ? null : _unlock, icon: const Icon(Icons.lock_open), label: Text(_busy ? 'Waiting for device…' : 'Unlock vault')),
      ]),
    )));
  }
}
