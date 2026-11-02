import 'dart:io';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/local_vault.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import 'file_preview_screen.dart';
import 'cloud_files_screen.dart';
import 'recovery_screen.dart';
import '../models/vault_file.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    required this.vault,
    this.isHiddenVault = false,
  });
  final LocalVault vault;
  final bool isHiddenVault;

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
  bool _hasCloudSession = false;
  final Map<String, double> _uploadProgress = {};
  final Set<String> _cancelledUploads = {};

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
    final files = await widget.vault.listFiles(isHidden: widget.isHiddenVault);
    final hasCloudSession = await _api.hasSession;
    if (mounted) {
      setState(() {
        _files = files;
        _hasCloudSession = hasCloudSession;
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
      await widget.vault.importFile(
        source,
        file.name,
        mime,
        isHidden: widget.isHiddenVault,
      );
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
    // Auto-sync newly imported files with cloud if linked
    if (imported > 0 && await _api.hasSession) {
      _sync(silent: true);
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

  Future<void> _uploadFile(VaultFile file) async {
    if (!await _api.hasSession) {
      _account();
      return;
    }
    setState(() {
      _message = 'Uploading "${file.name}"…';
      _uploadProgress[file.id] = 0;
      _cancelledUploads.remove(file.id);
      _files = _files
          .map(
            (item) =>
                item.id == file.id ? _withSyncState(item, 'uploading') : item,
          )
          .toList();
    });
    try {
      await _api.uploadSingleFile(
        file,
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(
            () => _uploadProgress[file.id] = total == 0 ? 0 : sent / total,
          );
        },
        isCancelled: () => _cancelledUploads.contains(file.id),
      );
      await _reload();
      if (mounted) {
        setState(() => _message = '“${file.name}” is synced.');
      }
    } on UploadCancelled {
      if (mounted) {
        setState(
          () => _message = 'Upload cancelled. The encrypted file stays on this device and can be retried.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = 'Upload interrupted. The encrypted file stays on this device. Retry when you’re online.',
        );
      }
    } finally {
      _cancelledUploads.remove(file.id);
      _uploadProgress.remove(file.id);
      await _reload();
    }
  }

  void _cancelUpload(String id) {
    setState(() {
      _cancelledUploads.add(id);
      _message = 'Cancelling upload… The local encrypted copy will be kept.';
    });
  }

  VaultFile _withSyncState(VaultFile file, String state) => VaultFile(
    id: file.id,
    name: file.name,
    mimeType: file.mimeType,
    size: file.size,
    createdAt: file.createdAt,
    localPath: file.localPath,
    syncState: state,
    folderName: file.folderName,
    remoteUpdatedAt: file.remoteUpdatedAt,
    isHidden: file.isHidden,
  );

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
    final userEmail = await _api.userEmail;
    if (!mounted) return;
    if (hasSession) {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              if (userEmail != null)
                ListTile(
                  leading: const Icon(Icons.account_circle, color: Colors.blue),
                  title: Text(
                    userEmail,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Cloud account signed in · sync runs when online',
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync with Cloud (Upload & Download)'),
                subtitle: const Text(
                  'Upload new files and download from other phones',
                ),
                onTap: () => Navigator.pop(context, 'sync'),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Browse Cloud Vault Files'),
                subtitle: const Text('View and download files in this account'),
                onTap: () => Navigator.pop(context, 'cloud'),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Recovery and device setup'),
                onTap: () => Navigator.pop(context, 'recovery'),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: Colors.red),
                ),
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
      await _sync();
      if (mounted) {
        setState(
          () => _message = 'Cloud account connected. File sync status appears beside each file.',
        );
      }
    }
  }

  Future<void> _sync({bool silent = false}) async {
    if (_syncing) return;
    _syncing = true;
    if (!silent && mounted) {
      setState(() => _message = 'Syncing encrypted files with cloud…');
    }
    try {
      final summary = await _api.syncAll(
        downloadMissing: true,
        onUploadProgress: (id, sent, total) {
          if (!mounted) return;
          setState(() {
            _uploadProgress[id] = total == 0 ? 0 : sent / total;
            _files = _files
                .map(
                  (file) =>
                      file.id == id ? _withSyncState(file, 'uploading') : file,
                )
                .toList();
          });
        },
        isUploadCancelled: (id) => _cancelledUploads.contains(id),
      );
      await _reload();
      if (mounted && !silent) {
        final parts = <String>[];
        if (summary.uploaded > 0) parts.add('${summary.uploaded} uploaded');
        if (summary.downloaded > 0) {
          parts.add('${summary.downloaded} downloaded');
        }
        setState(
          () => _message = parts.isEmpty
              ? 'Vault up to date (${summary.totalCloud} in cloud)'
              : 'Synced: ${parts.join(', ')}',
        );
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(
          () => _message = 'Could not sync with server. Local vault is safe.',
        );
      }
    } finally {
      final cancelled = _cancelledUploads.isNotEmpty;
      _syncing = false;
      _uploadProgress.clear();
      _cancelledUploads.clear();
      await _reload();
      if (cancelled && mounted) {
        setState(
          () => _message = 'Upload cancelled. The encrypted file remains on this device and can be retried.',
        );
      }
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
        title: Text(widget.isHiddenVault ? 'Hidden Safe' : 'Files'),
        actions: [
          IconButton(
            onPressed: () => _sync(silent: false),
            tooltip: 'Sync Cloud Files',
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            onPressed: _account,
            tooltip: 'Cloud account and recovery',
            icon: const Icon(Icons.account_circle_outlined),
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isHiddenVault ? 'Hidden Safe' : 'Your files',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _import,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add files'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _hasCloudSession
                    ? 'Encrypted on this device · Cloud account signed in'
                    : 'Encrypted on this device · Sync when you connect an account',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
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
                    : RefreshIndicator(
                        onRefresh: () => _sync(silent: false),
                        child: ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _fileCard(context, visible[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open_outlined, size: 40),
          const SizedBox(height: 8),
          Text(
            _query.isEmpty ? 'Nothing here yet' : 'No matching files',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _query.isEmpty
                ? 'Add a document or photo. It stays encrypted on this device until you sync it.'
                : 'Try another name.',
          ),
          if (_query.isEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _import,
              icon: const Icon(Icons.add),
              label: const Text('Add a file or photo'),
            ),
            if (_hasCloudSession) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CloudFilesScreen(vault: widget.vault, api: _api),
                  ),
                ),
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Browse synced files'),
              ),
            ],
          ],
        ],
      ),
    ),
  );

  Widget _fileCard(BuildContext context, VaultFile file) => Card(
    child: ListTile(
      isThreeLine: file.syncState == 'uploading',
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_size(file.size)} · ${file.folderName ?? 'No folder'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _syncStatus(context, file),
              if (file.syncState == 'uploading')
                Text(
                    _uploadProgress.containsKey(file.id)
                        ? '${((_uploadProgress[file.id] ?? 0) * 100).round()}%'
                        : 'Preparing upload…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            ],
          ),
          if (file.syncState == 'uploading') ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: _uploadProgress[file.id]),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'File actions',
        onSelected: (value) async {
          if (value == 'upload') _uploadFile(file);
          if (value == 'cancel') _cancelUpload(file.id);
          if (value == 'delete') _delete(file);
          if (value == 'rename') _rename(file);
          if (value == 'folder') _moveToFolder(file);
          if (value == 'resolve') _resolveConflict(file);
          if (value == 'toggle_hidden') {
            await widget.vault.toggleFileHidden(file.id, !file.isHidden);
            await _reload();
          }
        },
        itemBuilder: (_) => [
          if (file.syncState == 'uploading')
            const PopupMenuItem(
              value: 'cancel',
              child: Row(
                children: [
                  Icon(Icons.close_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Cancel upload'),
                ],
              ),
            )
          else if (file.syncState != 'synced' && file.syncState != 'conflict')
            const PopupMenuItem(
              value: 'upload',
              child: Row(
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Retry upload'),
                ],
              ),
            ),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'folder', child: Text('Move to folder')),
          PopupMenuItem(
            value: 'toggle_hidden',
            child: Text(
              file.isHidden ? 'Move to normal vault' : 'Move to hidden safe',
            ),
          ),
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

  Widget _syncStatus(BuildContext context, VaultFile file) {
    final (label, icon, color) = switch (file.syncState) {
      'synced' => ('Synced', Icons.cloud_done_rounded, Colors.green),
      'uploading' => ('Uploading', Icons.cloud_upload_outlined, Colors.blue),
      'failed' || 'conflict' => (
        'Needs attention',
        Icons.warning_amber_rounded,
        Colors.orange,
      ),
      'queued' || 'rename_pending' when _hasCloudSession => (
        'Queued',
        Icons.cloud_queue_rounded,
        Colors.blueGrey,
      ),
      _ => ('On this device', Icons.phone_android_rounded, Colors.blueGrey),
    };
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Sync status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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
      final email = _email.text.trim().toLowerCase();
      final password = _password.text;
      final localAuth = AuthService();
      if (await localAuth.isRegistered()) {
        final localEmail = (await localAuth.getUserEmail())?.toLowerCase();
        final localPassword = await localAuth.getPassword();
        if (localEmail != email || localPassword != password) {
          throw StateError(
            'Use the email and password that unlocked this device. Different credentials derive a different vault key and cannot safely merge the files already stored here.',
          );
        }
      }
      await ApiClient(LocalVault())
          .authenticate(email, password, createAccount: _create);
      await LocalVault().setMasterKeyFromCredentials(email, password);
      await AuthService().saveAccountCredentials(
        email: email,
        password: password,
        cloudAccount: true,
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
    title: Text(_create ? 'Create Account' : 'Link Email & Sync'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Use the same email and password as this device to keep its vault key. Files are encrypted before upload. On a new device, restore the vault with your recovery code, then download files for offline access.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email Address'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Master Password'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
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
