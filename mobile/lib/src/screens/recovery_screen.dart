import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/local_vault.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.vault, required this.api});
  final LocalVault vault;
  final ApiClient api;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _saved = false;
  String? _newCode;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadPendingCode();
  }

  Future<void> _loadPendingCode() async {
    final code = await widget.api.pendingRecoveryCode();
    if (mounted && code != null) setState(() => _newCode = code);
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<bool> _confirmReplace() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Create a new recovery code?'),
          content: const Text(
            'This replaces the account’s previous recovery code. Any older copy will stop working.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace code'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _create() async {
    if (!await _confirmReplace()) return;
    setState(() {
      _busy = true;
      _message = null;
      _newCode = null;
      _saved = false;
    });
    try {
      final code = await widget.api.createRecoveryCode();
      if (mounted) setState(() => _newCode = code);
    } catch (e) {
      if (mounted) {
        setState(() => _message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.restoreWithRecoveryCode(_code.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _newCode == null || _saved,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _newCode != null && !_saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Save the recovery code before leaving this screen.'),
          ),
        );
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Recovery and device setup')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.key_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
            'Keep access to your vault',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'A recovery code encrypts a copy of your vault key. The server stores only the encrypted envelope. Keep the code somewhere private; we cannot recover it for you.',
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add),
            label: const Text('Create or replace recovery code'),
          ),
          if (_newCode != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Write down this code now',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _newCode!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This code is shown only once. If lost, create a new one on this device before switching devices.',
                    ),
                    CheckboxListTile(
                      value: _saved,
                      onChanged: (value) =>
                          setState(() => _saved = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('I saved this recovery code securely'),
                    ),
                    FilledButton(
                      onPressed: _saved
                          ? () async {
                              await widget.api.acknowledgeRecoveryCode();
                              if (mounted) setState(() => _newCode = null);
                            }
                          : null,
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Divider(height: 40),
          Text(
            'Restore on this device',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign in to the same account, then enter its recovery code. Restoring replaces an empty local vault key; it cannot overwrite files already stored only on this device.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '43-character recovery code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: Text(_busy ? 'Working…' : 'Restore vault key'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}
