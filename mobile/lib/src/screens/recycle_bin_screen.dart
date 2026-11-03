import 'package:flutter/material.dart';

import '../data/firebase_sync_service.dart';
import '../data/local_vault.dart';
import '../models/vault_file.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({
    super.key,
    required this.vault,
    this.isHiddenVault = false,
  });
  final LocalVault vault;
  final bool isHiddenVault;

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<VaultFile> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await widget.vault.listTrashedFiles(
      isHidden: widget.isHiddenVault,
    );
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
      });
    }
  }

  Future<void> _restore(VaultFile file) async {
    await widget.vault.restoreFile(file.id);
    await widget.vault.addNotification(
      'File restored',
      file.name,
      type: 'activity',
      isHidden: widget.isHiddenVault,
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Restored “${file.name}”.')));
    }
  }

  Future<void> _deleteForever(VaultFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '“${file.name}” will be removed from this device. If it has a cloud copy, deletion will sync when you next connect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.vault.permanentlyDeleteFile(file);
    await widget.vault.addNotification(
      'Permanently deleted',
      file.name,
      type: 'trash',
      isHidden: widget.isHiddenVault,
    );
    if (!widget.isHiddenVault) {
      try {
        await FirebaseSyncService(widget.vault).deleteCloudFile(file.id);
      } catch (_) {}
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recycle Bin')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _files.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 48),
                  SizedBox(height: 12),
                  Text('Recycle Bin is empty'),
                  SizedBox(height: 6),
                  Text(
                    'Deleted files stay here until you restore or permanently delete them.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final file = _files[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    file.mimeType.startsWith('image/')
                        ? Icons.image_outlined
                        : Icons.description_outlined,
                  ),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_size(file.size)} · ${file.syncState == 'synced' ? 'Cloud delete waits until permanent deletion' : 'Stored on this device'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Recycle Bin actions',
                    onSelected: (action) => action == 'restore'
                        ? _restore(file)
                        : _deleteForever(file),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'restore', child: Text('Restore')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete forever'),
                      ),
                    ],
                  ),
                  onTap: () => _restore(file),
                ),
              );
            },
          ),
  );

  String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
