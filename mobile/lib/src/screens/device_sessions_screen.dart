import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/local_vault.dart';

class DeviceSessionsScreen extends StatefulWidget {
  const DeviceSessionsScreen({super.key, required this.vault});
  final LocalVault vault;

  @override
  State<DeviceSessionsScreen> createState() => _DeviceSessionsScreenState();
}

class _DeviceSessionsScreenState extends State<DeviceSessionsScreen> {
  late final ApiClient _api = ApiClient(widget.vault);
  List<Map<String, dynamic>> _devices = [];
  String? _currentId;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final devices = await _api.getDevices();
      final currentId = await _api.currentSessionId;
      if (mounted) {
        setState(() {
          _devices = devices;
          _currentId = currentId;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    final id = device['id'] as String?;
    if (id == null) return;
    final isCurrent = id == _currentId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isCurrent ? 'Sign out this device?' : 'Revoke this device?',
        ),
        content: Text(
          isCurrent
              ? 'This device will be signed out of cloud sync. Its encrypted files stored locally will remain available.'
              : 'This device will lose access to cloud services the next time it connects. Files already downloaded to it are not remotely erased.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isCurrent ? 'Sign out' : 'Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.revokeDevice(id);
      if (isCurrent) {
        await _api.signOut();
        if (mounted) Navigator.pop(context, true);
      } else {
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device access revoked.')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return 'Activity time unavailable';
    final date =
        '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    final time =
        '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    return 'Last active $date at $time';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Signed-in devices'),
      actions: [
        IconButton(
          onPressed: _load,
          tooltip: 'Refresh devices',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : _devices.isEmpty
          ? const Center(child: Text('No active cloud devices.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Revoke access if a device is lost. This blocks its cloud session, but cannot erase files already downloaded to that device.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                ..._devices.map((device) {
                  final current = device['id'] == _currentId;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        current ? Icons.phone_android : Icons.devices_outlined,
                      ),
                      title: Text(
                        (device['deviceName'] as String?) ?? 'Keepsake device',
                      ),
                      subtitle: Text(
                        '${current ? 'This device · ' : ''}${_date(device['lastSeenAt'])}',
                      ),
                      isThreeLine: false,
                      trailing: IconButton(
                        onPressed: () => _revoke(device),
                        tooltip: current
                            ? 'Sign out this device'
                            : 'Revoke device access',
                        icon: Icon(
                          current ? Icons.logout : Icons.remove_circle_outline,
                          color: current
                              ? null
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    ),
  );
}
