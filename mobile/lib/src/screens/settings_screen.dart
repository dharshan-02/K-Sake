import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../data/local_vault.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/firebase_sync_service.dart';
import '../models/theme_settings.dart';
import '../widgets/pattern_lock_view.dart';
import 'recovery_screen.dart';
import 'cloud_files_screen.dart';
import 'device_sessions_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.vault,
    required this.onLockNow,
    this.isHiddenVault = false,
  });

  final LocalVault vault;
  final VoidCallback onLockNow;
  final bool isHiddenVault;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  AuthLockType _lockType = AuthLockType.password;
  String _hiddenPin = '';
  bool _hiddenEnabled = false;
  int _autoLockMin = 0;
  Map<String, dynamic> _stats = {
    'fileCount': 0,
    'totalBytes': 0,
    'noteCount': 0,
    'credentialCount': 0,
  };
  String? _userEmail;
  String _accountMode = 'device';
  String _serverUrl = 'http://10.0.2.2:3000/v1';
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final type = await _authService.getPreferredLockType();
    final hPin = await _authService.getHiddenVaultPin();
    final hEnabled = await _authService.isHiddenVaultEnabled();
    final autoMin = await _authService.getAutoLockMinutes();
    final stats = await widget.vault.getVaultStats(
      isHidden: widget.isHiddenVault,
    );
    final fb = FirebaseSyncService(widget.vault);
    final api = ApiClient(widget.vault);
    final hasSession = fb.isAuthenticated || await api.hasSession;
    final email = fb.userEmail ?? await api.userEmail ?? await _authService.getUserEmail();
    final accountMode = await _authService.getAccountMode();
    final sUrl = await ApiClient.getBaseUrl();

    if (mounted) {
      setState(() {
        _lockType = type;
        _hiddenPin = hPin;
        _hiddenEnabled = hEnabled;
        _autoLockMin = autoMin;
        _stats = stats;
        _hasSession = hasSession;
        _userEmail = email;
        _accountMode = accountMode;
        _serverUrl = sUrl;
      });
    }
  }

  Future<void> _showChangeServerUrlDialog() async {
    final ctrl = TextEditingController(text: _serverUrl);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend Server Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the backend API URL for multi-device sync. Use 10.0.2.2 for emulator, or your computer\'s local Wi-Fi IP for real Android phones.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'http://10.0.2.2:3000/v1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Emulator (10.0.2.2)'),
                  onPressed: () => ctrl.text = 'http://10.0.2.2:3000/v1',
                ),
                ActionChip(
                  label: const Text('Localhost'),
                  onPressed: () => ctrl.text = 'http://localhost:3000/v1',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (updated != null && updated.isNotEmpty) {
      await ApiClient.setBaseUrl(updated);
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Server URL set to: $updated')));
      }
    }
  }

  Future<void> _syncNow() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fb = FirebaseSyncService(widget.vault);
      if (fb.isAuthenticated) {
        final summary = await fb.syncAll(downloadMissing: true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Sync complete: ${summary.uploaded} uploaded, ${summary.downloaded} downloaded.',
            ),
          ),
        );
      } else {
        final summary = await ApiClient(widget.vault)
            .syncAll(downloadMissing: true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Sync complete: ${summary.uploaded} uploaded, ${summary.downloaded} downloaded.',
            ),
          ),
        );
      }
      await _loadSettings();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
  }

  Future<void> _signOutAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out of account?'),
        content: const Text(
          'Files remain encrypted on this phone. Signing out pauses cloud sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseSyncService(widget.vault).signOut();
      await ApiClient(widget.vault).signOut();
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out successfully.')),
        );
      }
    }
  }

  Future<void> _deleteCloudAccount() async {
    final passwordController = TextEditingController();
    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Permanently delete cloud account?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This permanently deletes your cloud account, signed-in devices, recovery data, and encrypted cloud files. Local files on this phone stay here as a device-only vault.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  onChanged: (_) => setDialogState(() {}),
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Confirm account password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmationController,
                  onChanged: (_) => setDialogState(() {}),
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE to confirm',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed:
                  passwordController.text.isNotEmpty &&
                      confirmationController.text.trim() == 'DELETE'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      ),
    );
    final password = passwordController.text;
    passwordController.dispose();
    confirmationController.dispose();
    if (confirmed != true) return;

    try {
      await ApiClient(widget.vault).deleteAccount(password);
      await _authService.setAccountMode('device');
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cloud account deleted. This phone is now device-only; local files remain available.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account deletion failed: $error')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _showChangePinDialog() async {
    final pinCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change PIN'),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New 4-6 digit PIN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newPin = pinCtrl.text.trim();
              if (newPin.length >= 4 && newPin.length <= 6) {
                final messenger = ScaffoldMessenger.of(context);
                if (newPin == await _authService.getHiddenVaultPin()) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Choose a PIN different from your Hidden Safe PIN.',
                      ),
                    ),
                  );
                  return;
                }
                await _authService.setPin(newPin);
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  const SnackBar(content: Text('PIN updated successfully.')),
                );
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeHiddenPinDialog() async {
    final pinCtrl = TextEditingController(text: _hiddenPin);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Hidden Safe PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entering this PIN opens the Hidden Safe. It stays on this device and is not uploaded or synced.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Hidden Safe PIN',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final enteredPin = pinCtrl.text.trim();
              if (enteredPin.length >= 4 && enteredPin.length <= 6) {
                final messenger = ScaffoldMessenger.of(context);
                if (enteredPin == await _authService.getPin()) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Choose a PIN different from your regular vault PIN.',
                      ),
                    ),
                  );
                  return;
                }
                await _authService.setHiddenVaultPin(enteredPin);
                if (mounted) setState(() => _hiddenPin = enteredPin);
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Hidden Safe PIN saved.')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePatternDialog() async {
    String? newPattern;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Draw New Pattern'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                newPattern != null
                    ? 'Pattern Recorded!'
                    : 'Connect at least 4 dots',
                style: TextStyle(
                  color: newPattern != null ? Colors.green : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              PatternLockView(
                dimension: 220,
                onComplete: (pattern) =>
                    setDlgState(() => newPattern = pattern),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: newPattern == null
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await _authService.setPattern(newPattern!);
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Unlock pattern updated.'),
                        ),
                      );
                    },
              child: const Text('Save Pattern'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeCtrl = AppThemeController.instance;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          if (widget.isHiddenVault) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.shield_moon_outlined),
                title: const Text('Hidden Safe'),
                subtitle: const Text(
                  'This area stays on this device and is not uploaded. It uses the same vault encryption key as regular files; moving an already synced file here queues its cloud copy for deletion.',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Theme Presets Section
          _buildSectionHeader('Appearance & Themes', Icons.palette_outlined),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Theme Preset',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select your preferred visual style',
                    style: TextStyle(color: theme.hintColor, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildThemeChip('Light', AppThemePreset.light, themeCtrl),
                      _buildThemeChip(
                        'Dark Slate',
                        AppThemePreset.dark,
                        themeCtrl,
                      ),
                      _buildThemeChip(
                        'Midnight AMOLED',
                        AppThemePreset.amoled,
                        themeCtrl,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Security Section
          _buildSectionHeader('Security & Biometrics', Icons.security_outlined),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('Preferred Unlock Method'),
                  subtitle: Text(_lockType.name.toUpperCase()),
                  trailing: DropdownButton<AuthLockType>(
                    value: _lockType,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: AuthLockType.biometric,
                        child: Text('Biometric'),
                      ),
                      DropdownMenuItem(
                        value: AuthLockType.pin,
                        child: Text('PIN'),
                      ),
                      DropdownMenuItem(
                        value: AuthLockType.pattern,
                        child: Text('Pattern'),
                      ),
                      DropdownMenuItem(
                        value: AuthLockType.password,
                        child: Text('Password'),
                      ),
                    ],
                    onChanged: (val) async {
                      if (val == null) return;
                      final messenger = ScaffoldMessenger.of(context);
                      if (val == AuthLockType.pin &&
                          await _authService.getPin() == null) {
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Set a vault PIN before choosing PIN unlock.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                      if (val == AuthLockType.pattern &&
                          await _authService.getPattern() == null) {
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Create a pattern before choosing pattern unlock.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                      if (val == AuthLockType.biometric) {
                        try {
                          final auth = LocalAuthentication();
                          final available = await auth.getAvailableBiometrics();
                          if (!await auth.canCheckBiometrics ||
                              available.isEmpty) {
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Set up biometrics in your device settings first.',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                        } catch (_) {
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Biometric unlock is not available on this device.',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                      }
                      await _authService.setPreferredLockType(val);
                      if (mounted) setState(() => _lockType = val);
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Biometrics gate access through the operating system; they are not stored by Keepsake and do not replace file encryption.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('Change Vault PIN'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showChangePinDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.gesture),
                  title: const Text('Change Pattern Lock'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showChangePatternDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Auto-Lock on Background'),
                  subtitle: Text(
                    _autoLockMin == 0
                        ? 'Immediately'
                        : 'After $_autoLockMin min',
                  ),
                  trailing: DropdownButton<int>(
                    value: _autoLockMin,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Immediately')),
                      DropdownMenuItem(value: 1, child: Text('1 minute')),
                      DropdownMenuItem(value: 5, child: Text('5 minutes')),
                      DropdownMenuItem(value: 15, child: Text('15 minutes')),
                    ],
                    onChanged: (val) async {
                      if (val != null) {
                        await _authService.setAutoLockMinutes(val);
                        setState(() => _autoLockMin = val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (!widget.isHiddenVault) ...[
            // Hidden Safe Setup
            _buildSectionHeader('Hidden Safe', Icons.visibility_off_outlined),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.shield_moon_outlined),
                    title: const Text('Enable Hidden Safe'),
                    subtitle: const Text(
                      'A separate PIN opens this local area. It uses the same vault encryption key; cloud files moved here are queued for deletion on next sync.',
                    ),
                    value: _hiddenEnabled,
                    onChanged: (val) async {
                      if (val && _hiddenPin.isEmpty) {
                        await _showChangeHiddenPinDialog();
                        if (_hiddenPin.isEmpty) return;
                      }
                      await _authService.setHiddenVaultEnabled(val);
                      setState(() => _hiddenEnabled = val);
                    },
                  ),
                  if (_hiddenEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.password_outlined),
                      title: const Text('Hidden Safe PIN'),
                      subtitle: const Text(
                        'A separate PIN opens the private area',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _showChangeHiddenPinDialog,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Storage Breakdown Section
          _buildSectionHeader('Storage & Cache', Icons.pie_chart_outline),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatColumn('Files', '${_stats['fileCount']}'),
                      _buildStatColumn(
                        'Storage',
                        _formatBytes(_stats['totalBytes'] as int),
                      ),
                      _buildStatColumn('Notes', '${_stats['noteCount']}'),
                      _buildStatColumn(
                        'Passwords',
                        '${_stats['credentialCount']}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: const Text('Clear Decrypted Preview Cache'),
                    subtitle: const Text(
                      'Safely purges decrypted temporary view files',
                    ),
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await widget.vault.clearPreviewCache();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Decrypted preview cache cleared.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (!widget.isHiddenVault) ...[
            // Multi-Device Cloud Sync Section
            _buildSectionHeader('Account & Sync', Icons.cloud_sync_outlined),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      _hasSession
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      color: _hasSession ? Colors.green : Colors.grey,
                    ),
                    title: Text(
                      _hasSession &&
                              _userEmail != null &&
                              _userEmail!.isNotEmpty
                          ? _userEmail!
                          : _hasSession
                          ? 'Cloud account · signed in'
                          : _accountMode == 'cloud'
                          ? 'Cloud account · signed out'
                          : 'Device-only vault',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _hasSession
                          ? 'Signed in. Encrypted copies sync when online; other devices need your recovery code.'
                          : _accountMode == 'cloud'
                          ? 'Your local files remain here. Sign in to sync again.'
                          : 'No cloud copy is configured. Files stay on this device.',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'File contents are encrypted before upload. File names, sizes, and sync timestamps remain visible to the cloud service.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: const Text('Sync with Cloud Now'),
                    subtitle: const Text(
                      'Upload queued files and download available cloud copies',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _hasSession
                        ? _syncNow
                        : () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Sign in to a cloud account to sync. Your files are still available on this device.',
                              ),
                            ),
                          ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Browse Cloud Files'),
                    subtitle: Text(
                      _hasSession
                          ? 'Inspect and download encrypted files in your account'
                          : 'Available after you sign in to a cloud account',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _hasSession
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CloudFilesScreen(
                                  vault: widget.vault,
                                  api: ApiClient(widget.vault),
                                ),
                              ),
                            );
                          }
                        : () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Sign in to a cloud account to browse cloud files.',
                              ),
                            ),
                          ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Backend Server URL'),
                    subtitle: Text(
                      _serverUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: _showChangeServerUrlDialog,
                  ),
                  if (_hasSession) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        'Sign Out',
                        style: TextStyle(color: Colors.red),
                      ),
                      subtitle: const Text(
                        'Files remain encrypted on this phone; signing out pauses cloud sync',
                      ),
                      onTap: _signOutAccount,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.delete_forever_outlined,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Permanently Delete Cloud Account',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: const Text(
                        'Deletes cloud files and account data after password confirmation',
                      ),
                      onTap: _deleteCloudAccount,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (!widget.isHiddenVault) ...[
            // Recovery & Account
            _buildSectionHeader('Recovery & Account', Icons.vpn_key_outlined),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Recovery code & device setup'),
                    subtitle: const Text(
                      'Restore this vault on a new device. Keep a private backup; losing the key and all unlocked devices means cloud files cannot be decrypted.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (!_hasSession) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'A recovery code needs a connected cloud account. Device-only files remain on this phone.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecoveryScreen(
                            vault: widget.vault,
                            api: ApiClient(widget.vault),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_hasSession) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.devices_outlined),
                      title: const Text('Signed-in devices'),
                      subtitle: const Text(
                        'Review devices and revoke cloud access',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (_) =>
                                DeviceSessionsScreen(vault: widget.vault),
                          ),
                        );
                        await _loadSettings();
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _buildSectionHeader('Access', Icons.lock_outline),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock, color: Colors.orangeAccent),
              title: const Text('Lock Vault Immediately'),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onLockNow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeChip(
    String label,
    AppThemePreset preset,
    AppThemeController ctrl,
  ) {
    final isSelected = ctrl.preset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => ctrl.setPreset(preset),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
        ),
      ],
    );
  }
}
