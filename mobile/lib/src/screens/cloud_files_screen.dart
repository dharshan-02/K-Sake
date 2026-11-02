import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/local_vault.dart';
import '../models/vault_file.dart';
import 'file_preview_screen.dart';

class CloudFilesScreen extends StatefulWidget {
  const CloudFilesScreen({super.key, required this.vault, required this.api});
  final LocalVault vault;
  final ApiClient api;

  @override
  State<CloudFilesScreen> createState() => _CloudFilesScreenState();
}

class _CloudFilesScreenState extends State<CloudFilesScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  String? _error;
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _files = await widget.api.listCloudFiles();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(Map<String, dynamic> file) async {
    final id = file['id'] as String;
    setState(() {
      _downloading.add(id);
      _error = null;
    });
    try {
      await widget.api.downloadToVault(file);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cloud files'),
      actions: [
        IconButton(
          onPressed: _refresh,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null && _files.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ),
          )
        : _files.isEmpty
        ? const Center(child: Text('No files have synced to this account yet.'))
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _fileTile(_files[index]),
          ),
  );

  Widget _fileTile(Map<String, dynamic> file) {
    final id = file['id'] as String;
    return FutureBuilder<VaultFile?>(
      future: widget.vault.findFile(id),
      builder: (context, snapshot) {
        final local = snapshot.data;
        final downloading = _downloading.contains(id);
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.cloud_outlined)),
            title: Text(
              file['name'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              local != null
                  ? 'Available offline'
                  : 'Encrypted in cloud · download to this device',
            ),
            trailing: local != null
                ? IconButton(
                    tooltip: 'Open file',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            FilePreviewScreen(vault: widget.vault, file: local),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Download encrypted file',
                    icon: downloading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    onPressed: downloading ? null : () => _download(file),
                  ),
          ),
        );
      },
    );
  }
}
