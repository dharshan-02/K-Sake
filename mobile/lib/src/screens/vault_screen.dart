import 'dart:io';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/local_vault.dart';
import '../data/api_client.dart';
import 'file_preview_screen.dart';
import 'cloud_files_screen.dart';
import 'recovery_screen.dart';
import '../models/vault_file.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.vault});
  final LocalVault vault;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<VaultFile> _files = [];
  bool _loading = true;
  String _query = '';
  String? _selectedFolder;
  String? _message;
  late final ApiClient _api = ApiClient(widget.vault);
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _connectivity = Connectivity().onConnectivityChanged.listen((states) {
      if (states.any((state) => state != ConnectivityResult.none)) {
        _sync(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final files = await widget.vault.listFiles();
    if (mounted) {
      setState(() {
        _files = files;
        if (_selectedFolder != null &&
            !files.any((f) => f.folderName == _selectedFolder)) {
          _selectedFolder = null;
        }
        _loading = false;
      });
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    var imported = 0;
    for (final file in result) {
      final source = file.path;
      if (source == null || !await File(source).exists()) continue;
      final ext = file.extension?.toLowerCase() ?? '';
      final mime = switch (ext) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'txt' => 'text/plain',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        _ => 'application/octet-stream',
      };
      await widget.vault.importFile(source, file.name, mime);
      imported++;
    }
    await _reload();
    if (mounted) {
      setState(
        () => _message = imported == 0
            ? 'No accessible files were imported.'
            : '$imported file${imported == 1 ? '' : 's'} encrypted on this device.',
      );
    }
  }

  Future<void> _delete(VaultFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this file?'),
        content: Text(
          '${file.name} will be removed from this device and queued for cloud deletion if it has synced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.vault.deleteFile(file);
      await _reload();
    }
  }

  Future<void> _rename(VaultFile file) async {
    final controller = TextEditingController(text: file.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 255,
          decoration: const InputDecoration(labelText: 'File name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == file.name) return;
    await widget.vault.renameFile(file, name);
    await _reload();
  }

  Future<void> _moveToFolder(VaultFile file) async {
    final controller = TextEditingController(text: file.folderName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            hintText: 'Leave blank for no folder',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await widget.vault.setFolder(file.id, name.isEmpty ? null : name);
    await _reload();
  }

  Future<void> _resolveConflict(VaultFile file) async {
    final keepLocal = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep this device’s name?'),
        content: Text(
          'A newer cloud change exists for “${file.name}”. This will set the cloud name to this device’s name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keep local name'),
          ),
        ],
      ),
    );
    if (keepLocal != true) return;
    try {
      await _api.keepLocalNameOnCloud(file);
      await _reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'The cloud copy changed again. Refresh and review it before resolving.',
        );
      }
    }
  }

  Future<void> _account() async {
    final hasSession = await _api.hasSession;
    if (!mounted) return;
    if (hasSession) {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync queued files'),
                onTap: () => Navigator.pop(context, 'sync'),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Browse cloud files'),
                onTap: () => Navigator.pop(context, 'cloud'),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Recovery and device setup'),
                onTap: () => Navigator.pop(context, 'recovery'),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () => Navigator.pop(context, 'signout'),
              ),
            ],
          ),
        ),
      );
      if (action == 'signout') {
        await _api.signOut();
        if (mounted) {
          setState(
            () =>
                _message = 'Signed out. Files remain available on this device.',
          );
        }
      }
      if (action == 'sync') {
        await _sync();
      }
      if (action == 'cloud' && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CloudFilesScreen(vault: widget.vault, api: _api),
          ),
        );
        await _reload();
      }
      if (action == 'recovery' && mounted) {
        final restored = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => RecoveryScreen(vault: widget.vault, api: _api),
          ),
        );
        await _reload();
        if (restored == true && mounted) {
          setState(
            () => _message = 'Vault key restored. Download your cloud files to use them offline.',
          );
        }
      }
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _AccountDialog(),
    );
    if (result == 'authenticated' && mounted) {
      setState(
        () => _message =
            'Account connected. Use the cloud button to sync encrypted files.',
      );
    }
  }

  Future<void> _sync({bool silent = false}) async {
    if (_syncing) return;
    _syncing = true;
    if (!silent && mounted) {
      setState(() => _message = 'Syncing encrypted files…');
    }
    try {
      final count = await _api.syncQueued();
      await _reload();
      if (mounted && !silent) {
        setState(
          () => _message = '$count file${count == 1 ? '' : 's'} synced.',
        );
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(
          () => _message = 'Could not sync. Your local files are safe; try again when online.',
        );
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders =
        _files
            .map((f) => f.folderName)
            .whereType<String>()
            .where((f) => f.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final visible = _files
        .where(
          (f) =>
              f.name.toLowerCase().contains(_query.toLowerCase()) &&
              (_selectedFolder == null || f.folderName == _selectedFolder),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keepsake'),
        actions: [
          IconButton(
            onPressed: _account,
            tooltip: 'Account and sync',
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
          IconButton(
            onPressed: _import,
            tooltip: 'Add files',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your private space',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Encrypted on this device. Ready to sync when online.',
              ),
              const SizedBox(height: 20),
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search files',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _message!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Files',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  DropdownButton<String?>(
                    value: _selectedFolder,
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All folders'),
                      ),
                      ...folders.map(
                        (f) => DropdownMenuItem<String?>(
                          value: f,
                          child: Text(f, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedFolder = value),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${visible.length}',
                    semanticsLabel: '${visible.length} files',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : visible.isEmpty
                    ? _empty(context)
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _fileCard(context, visible[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        icon: const Icon(Icons.upload_file),
        label: const Text('Add files'),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.folder_open_outlined, size: 48),
        const SizedBox(height: 12),
        Text(
          _query.isEmpty ? 'Your vault is ready' : 'No matching files',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          _query.isEmpty
              ? 'Add documents or photos to keep them protected here.'
              : 'Try another name.',
        ),
        if (_query.isEmpty) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.add),
            label: const Text('Choose files'),
          ),
        ],
      ],
    ),
  );

  Widget _fileCard(BuildContext context, VaultFile file) => Card(
    child: ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FilePreviewScreen(vault: widget.vault, file: file),
        ),
      ),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          file.mimeType.startsWith('image/') ||
                  file.name.toLowerCase().endsWith('.jpg') ||
                  file.name.toLowerCase().endsWith('.jpeg') ||
                  file.name.toLowerCase().endsWith('.png')
              ? Icons.image_outlined
              : Icons.description_outlined,
        ),
      ),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_size(file.size)} · ${switch (file.syncState) {
          'synced' => 'Synced',
          'uploading' => 'Uploading',
          'failed' => 'Sync failed · retry from cloud menu',
          'conflict' => 'Name conflict · review before syncing',
          _ => 'On device · Upload queued',
        }}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'File actions',
        onSelected: (value) {
          if (value == 'delete') _delete(file);
          if (value == 'rename') _rename(file);
          if (value == 'folder') _moveToFolder(file);
          if (value == 'resolve') _resolveConflict(file);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'folder', child: Text('Move to folder')),
          if (file.syncState == 'conflict')
            const PopupMenuItem(
              value: 'resolve',
              child: Text('Keep local name on cloud'),
            ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    ),
  );

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog();
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient(LocalVault()).authenticate(
        _email.text.trim(),
        _password.text,
        createAccount: _create,
      );
      if (mounted) Navigator.pop(context, 'authenticated');
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_create ? 'Create account' : 'Sign in to sync'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Files are encrypted on this device before upload. Account recovery is not implemented yet; keep another copy of important files.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(
              labelText: 'Password (12+ characters)',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _create = !_create),
            child: Text(
              _create
                  ? 'Already have an account? Sign in'
                  : 'New here? Create account',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(
          _busy
              ? 'Please wait…'
              : _create
              ? 'Create account'
              : 'Sign in',
        ),
      ),
    ],
  );
}
