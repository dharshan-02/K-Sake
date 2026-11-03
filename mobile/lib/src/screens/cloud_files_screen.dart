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
  bool _downloadingAll = false;
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
      await widget.vault.addNotification(
        'File downloaded',
        file['name'] as String,
        type: 'download',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Downloaded "${file['name']}"')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(id));
    }
  }

  Future<void> _downloadAll() async {
    if (_downloadingAll) return;
    setState(() => _downloadingAll = true);
    var count = 0;
    try {
      for (final file in _files) {
        final id = file['id'] as String;
        final local = await widget.vault.findFile(id, includeTrashed: true);
        if (local == null) {
          await widget.api.downloadToVault(file);
          await widget.vault.addNotification(
            'File downloaded',
            file['name'] as String,
            type: 'download',
          );
          count++;
          if (mounted) setState(() {});
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Downloaded $count file${count == 1 ? '' : 's'} to local vault.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download incomplete: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloadingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cloud Vault Files'),
      actions: [
        if (_downloadingAll)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          IconButton(
            onPressed: _downloadAll,
            tooltip: 'Download All Missing to Device',
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        IconButton(
          onPressed: _refresh,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: _loading
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
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _files.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text('No files have synced to this account yet.'),
                    const SizedBox(height: 6),
                    const Text(
                      'Upload files from any device linked to this email to see them here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _files.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _fileTile(_files[index]),
            ),
    ),
  );

  Widget _fileTile(Map<String, dynamic> file) {
    final id = file['id'] as String;
    return FutureBuilder<VaultFile?>(
      future: widget.vault.findFile(id),
      builder: (context, snapshot) {
        final local = snapshot.data;
        final downloading = _downloading.contains(id);
        final sizeBytes = (file['size'] as num?)?.toInt() ?? 0;
        final sizeStr = _size(sizeBytes);

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: local != null
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.blue.withValues(alpha: 0.15),
              child: Icon(
                local != null
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_download_outlined,
                color: local != null ? Colors.green : Colors.blue,
              ),
            ),
            title: Text(
              file['name'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              local != null
                  ? '$sizeStr · Available offline'
                  : '$sizeStr · In cloud · Tap download',
            ),
            trailing: local != null
                ? IconButton(
                    tooltip: 'Open decrypted file',
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

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
