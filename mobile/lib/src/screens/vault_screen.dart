import 'dart:io';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/local_vault.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/firebase_sync_service.dart';
import 'file_preview_screen.dart';
import 'cloud_files_screen.dart';
import 'recovery_screen.dart';
import 'recycle_bin_screen.dart';
import '../widgets/folder_name_dialog.dart';
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
  String _selectedType = 'all';
  String _selectedSync = 'all';
  String _selectedDate = 'all';
  String? _message;
  late final ApiClient _api = ApiClient(widget.vault);
  late final FirebaseSyncService _firebaseSync = FirebaseSyncService(widget.vault);
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
    final hasCloudSession = widget.isHiddenVault
        ? false
        : (_firebaseSync.isAuthenticated || await _api.hasSession);
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
    if (imported > 0 && !widget.isHiddenVault && await _api.hasSession) {
      _sync(silent: true);
    }
  }

  Future<void> _delete(VaultFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Recycle Bin?'),
        content: Text(
          '${file.name} will stay in Recycle Bin until you restore it or permanently delete it.',
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
      await widget.vault.addNotification(
        'Moved to Recycle Bin',
        file.name,
        type: 'trash',
        isHidden: widget.isHiddenVault,
      );
      await _reload();
    }
  }

  Future<void> _rename(VaultFile file) async {
    var updatedName = file.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename file'),
        content: TextFormField(
          initialValue: file.name,
          autofocus: true,
          maxLength: 255,
          decoration: const InputDecoration(labelText: 'File name'),
          onChanged: (value) => updatedName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, updatedName.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == file.name) return;
    await widget.vault.renameFile(file, name);
    await _reload();
  }

  Future<void> _moveToFolder(VaultFile file) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => FolderNameDialog(
        title: 'Move to folder',
        submitLabel: 'Save',
        fieldLabel: 'Folder name',
        hintText: 'Leave blank for no folder',
        initialName: file.folderName ?? '',
      ),
    );
    if (name == null) return;
    await widget.vault.setFolder(file.id, name.isEmpty ? null : name);
    await _reload();
  }

  Future<void> _createFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const FolderNameDialog(
        title: 'Create folder',
        submitLabel: 'Create',
        fieldLabel: 'Folder name',
        hintText: 'For example, Receipts',
      ),
    );
    if (!mounted || name == null) return;
    try {
      await widget.vault.createFolder(name, isHidden: widget.isHiddenVault);
      await _reload();
      if (mounted) {
        setState(() {
          _selectedFolder = name;
          _message = 'Folder created. Move files into it from a file’s menu.';
        });
      }
    } catch (error) {
      if (mounted) {
        final message = error is FormatException || error is StateError
            ? error
                  .toString()
                  .replaceFirst('FormatException: ', '')
                  .replaceFirst('Bad state: ', '')
            : 'Could not create the folder. Please try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _showFilters() async {
    var type = _selectedType;
    var sync = _selectedSync;
    var date = _selectedDate;
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Filter files',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _filterChoices(context, 'File type', type, const {
                  'all': 'All types',
                  'image': 'Photos',
                  'pdf': 'PDFs',
                  'document': 'Documents',
                  'other': 'Other',
                }, (value) => setSheetState(() => type = value)),
                _filterChoices(context, 'Sync status', sync, const {
                  'all': 'Any status',
                  'local': 'On this device',
                  'queued': 'Queued',
                  'uploading': 'Uploading',
                  'synced': 'Synced',
                  'attention': 'Needs attention',
                }, (value) => setSheetState(() => sync = value)),
                _filterChoices(context, 'Date added', date, const {
                  'all': 'Any time',
                  '7': 'Past 7 days',
                  '30': 'Past 30 days',
                  '365': 'Past year',
                }, (value) => setSheetState(() => date = value)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, const {
                        'type': 'all',
                        'sync': 'all',
                        'date': 'all',
                      }),
                      child: const Text('Clear filters'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, {
                        'type': type,
                        'sync': sync,
                        'date': date,
                      }),
                      child: const Text('Show results'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedType = result['type'] ?? 'all';
        _selectedSync = result['sync'] ?? 'all';
        _selectedDate = result['date'] ?? 'all';
      });
    }
  }

  Widget _filterChoices(
    BuildContext context,
    String title,
    String selected,
    Map<String, String> choices,
    ValueChanged<String> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        Wrap(
          spacing: 8,
          children: choices.entries
              .map(
                (entry) => ChoiceChip(
                  label: Text(entry.value),
                  selected: selected == entry.key,
                  onSelected: (_) => onChanged(entry.key),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );

  String _typeFor(VaultFile file) {
    final mime = file.mimeType.toLowerCase();
    final ext = file.name.toLowerCase().split('.').last;
    if (mime.startsWith('image/') ||
        {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(ext)) {
      return 'image';
    }
    if (mime == 'application/pdf' || ext == 'pdf') return 'pdf';
    if (mime.startsWith('text/') ||
        {
          'doc',
          'docx',
          'odt',
          'rtf',
          'txt',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
        }.contains(ext)) {
      return 'document';
    }
    return 'other';
  }

  Future<void> _uploadFile(VaultFile file) async {
    if (widget.isHiddenVault) return;
    if (!_firebaseSync.isAuthenticated && !await _api.hasSession) {
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
      if (_firebaseSync.isAuthenticated) {
        await _firebaseSync.uploadFile(file);
      } else {
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
      }
      await widget.vault.addNotification(
        'Upload complete',
        file.name,
        type: 'upload',
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
      await widget.vault.addNotification(
        'Upload needs attention',
        file.name,
        type: 'error',
      );
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
    if (widget.isHiddenVault) return;
    final hasSession = _firebaseSync.isAuthenticated || await _api.hasSession;
    final userEmail = _firebaseSync.userEmail ?? await _api.userEmail;
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
                  subtitle: Text(
                    _firebaseSync.isAuthenticated
                        ? 'Firebase cloud active · Zero-knowledge encrypted sync'
                        : 'Cloud account signed in · sync runs when online',
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
        if (_firebaseSync.isAuthenticated) {
          await _firebaseSync.signOut();
        }
        await _api.signOut();
        await _reload();
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
    if (widget.isHiddenVault) return;
    if (_syncing) return;
    _syncing = true;
    if (!silent && mounted) {
      setState(() => _message = 'Syncing encrypted files with cloud…');
    }
    try {
      if (_firebaseSync.isAuthenticated) {
        final summary = await _firebaseSync.syncAll(downloadMissing: true);
        if (summary.uploaded > 0) {
          await widget.vault.addNotification(
            'Uploads complete',
            '${summary.uploaded} file${summary.uploaded == 1 ? '' : 's'} synced to your cloud vault.',
            type: 'upload',
          );
        }
        if (summary.downloaded > 0) {
          await widget.vault.addNotification(
            'Downloads complete',
            '${summary.downloaded} cloud file${summary.downloaded == 1 ? '' : 's'} are available offline.',
            type: 'download',
          );
        }
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
      } else {
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
        if (summary.uploaded > 0) {
          await widget.vault.addNotification(
            'Uploads complete',
            '${summary.uploaded} file${summary.uploaded == 1 ? '' : 's'} synced to your cloud vault.',
            type: 'upload',
          );
        }
        if (summary.downloaded > 0) {
          await widget.vault.addNotification(
            'Downloads complete',
            '${summary.downloaded} cloud file${summary.downloaded == 1 ? '' : 's'} are available offline.',
            type: 'download',
          );
        }
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
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(
          () => _message = 'Could not reach cloud. Your encrypted files are safe on this device and can be synced later.',
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
    final folders = widget.vault.listFolders(isHidden: widget.isHiddenVault);
    final cutoff = _selectedDate == 'all'
        ? null
        : DateTime.now().subtract(Duration(days: int.parse(_selectedDate)));
    final visible = _files
        .where(
          (f) =>
              f.name.toLowerCase().contains(_query.toLowerCase()) &&
              (_selectedFolder == null || f.folderName == _selectedFolder) &&
              (_selectedType == 'all' || _typeFor(f) == _selectedType) &&
              (_selectedSync == 'all' ||
                  switch (_selectedSync) {
                    'local' =>
                      f.syncState == 'local' ||
                          (!_hasCloudSession &&
                              (f.syncState == 'queued' ||
                                  f.syncState == 'rename_pending')),
                    'queued' =>
                      f.syncState == 'queued' ||
                          f.syncState == 'rename_pending',
                    'uploading' => f.syncState == 'uploading',
                    'synced' => f.syncState == 'synced',
                    'attention' =>
                      f.syncState == 'failed' || f.syncState == 'conflict',
                    _ => true,
                  }) &&
              (cutoff == null || !f.createdAt.isBefore(cutoff)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isHiddenVault ? 'Hidden Safe' : 'Files'),
        actions: [
          if (!widget.isHiddenVault) ...[
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
          ],
          IconButton(
            onPressed: () => Navigator.of(context)
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecycleBinScreen(
                      vault: widget.vault,
                      isHiddenVault: widget.isHiddenVault,
                    ),
                  ),
                )
                .then((_) => _reload()),
            tooltip: 'Recycle Bin',
            icon: const Icon(Icons.delete_outline),
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
                widget.isHiddenVault
                    ? 'Private local safe · Never uploaded or synced'
                    : _hasCloudSession
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
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Searches names in this device’s vault.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showFilters,
                      icon: Icon(
                        Icons.tune,
                        size: 18,
                        color:
                            (_selectedType != 'all' ||
                                _selectedSync != 'all' ||
                                _selectedDate != 'all')
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      label: Text(
                        (_selectedType != 'all' ||
                                _selectedSync != 'all' ||
                                _selectedDate != 'all')
                            ? 'Filters on'
                            : 'Filter',
                      ),
                    ),
                  ],
                ),
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
                  IconButton(
                    onPressed: _createFolder,
                    tooltip: 'Create folder',
                    icon: const Icon(Icons.create_new_folder_outlined),
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
            _query.isEmpty
                ? (_selectedFolder == null
                      ? 'Nothing here yet'
                      : 'This folder is empty')
                : 'No matching files',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _query.isEmpty
                ? (_selectedFolder == null
                      ? 'Add a document or photo. It stays encrypted on this device until you sync it.'
                      : 'Move files here from a file’s menu, or add a file to this folder after importing it.')
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
          if (value == 'toggle_hidden' && !widget.isHiddenVault) {
            await widget.vault.toggleFileHidden(file.id, !file.isHidden);
            await _reload();
            if (!file.isHidden && _hasCloudSession) _sync(silent: true);
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
          if (!widget.isHiddenVault)
            PopupMenuItem(
              value: 'toggle_hidden',
              child: Text(
                file.isHidden ? 'Move to regular files' : 'Move to Hidden Safe',
              ),
            ),
          if (file.syncState == 'conflict')
            const PopupMenuItem(
              value: 'resolve',
              child: Text('Keep local name on cloud'),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Move to Recycle Bin'),
          ),
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
      try {
        final fb = FirebaseSyncService(LocalVault());
        if (_create) {
          await fb.signUp(email, password);
        } else {
          await fb.signIn(email, password);
        }
      } catch (fbErr) {
        // If Firebase throws, also try legacy/local ApiClient
        try {
          await ApiClient(LocalVault())
              .authenticate(email, password, createAccount: _create);
        } catch (_) {
          rethrow;
        }
      }
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
