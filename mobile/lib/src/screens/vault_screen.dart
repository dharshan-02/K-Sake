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
    final folders = widget.vault.listFolders(isHidden: widget.isHiddenVault);
    if (mounted) {
      setState(() {
        _files = files;
        _hasCloudSession = hasCloudSession;
        if (_selectedFolder != null && !folders.contains(_selectedFolder)) {
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
        folderName: _selectedFolder,
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

  Future<void> _deleteFolder(String folderName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete folder "$folderName"?'),
        content: const Text(
          'Files inside this folder will stay in your vault as unassigned files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.vault.deleteFolder(folderName, isHidden: widget.isHiddenVault);
      if (_selectedFolder == folderName) {
        _selectedFolder = null;
      }
      await _reload();
      if (mounted) {
        setState(() => _message = 'Folder "$folderName" removed.');
      }
    }
  }

  Future<void> _renameFolder(String oldName) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => FolderNameDialog(
        title: 'Rename folder',
        submitLabel: 'Rename',
        fieldLabel: 'Folder name',
        hintText: 'Enter new folder name',
        initialName: oldName,
      ),
    );
    if (newName == null || newName.trim().isEmpty || newName.trim() == oldName) return;
    try {
      await widget.vault.renameFolder(oldName, newName.trim(), isHidden: widget.isHiddenVault);
      if (_selectedFolder == oldName) {
        _selectedFolder = newName.trim();
      }
      await _reload();
      if (mounted) {
        setState(() => _message = 'Folder renamed to "$newName".');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  void _showFolderOptions(String folderName) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  const Icon(Icons.folder_rounded, color: Color(0xFFE09F3E), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      folderName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename folder'),
              onTap: () {
                Navigator.pop(ctx);
                _renameFolder(folderName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete folder', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Files will be kept in vault, unassigned'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteFolder(folderName);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add files', style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 2,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: (_selectedType != 'all' ||
                              _selectedSync != 'all' ||
                              _selectedDate != 'all')
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Filter files',
                    onPressed: _showFilters,
                  ),
                  hintText: 'Search encrypted vault...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),

            // Quick Category Filters
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _filterChip('all', 'All Files'),
                  const SizedBox(width: 8),
                  _filterChip('image', 'Photos'),
                  const SizedBox(width: 8),
                  _filterChip('pdf', 'PDFs'),
                  const SizedBox(width: 8),
                  _filterChip('document', 'Docs'),
                ],
              ),
            ),

            // Prominent Folders Section Outside on Screen
            _buildFoldersSection(context, folders, _files),

            // Active Folder Filter Indicator
            if (_selectedFolder != null)
              _buildActiveFolderBanner(context),

            if (_message != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _message = null),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 6),

            // Files List or Empty State
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? _empty(context)
                  : RefreshIndicator(
                      onRefresh: () => _sync(silent: false),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88, top: 4),
                        itemCount: visible.length,
                        itemBuilder: (context, index) =>
                            _fileCard(context, visible[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String type, String label) {
    final selected = _selectedType == type;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final inFolder = _selectedFolder != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: inFolder
                    ? const Color(0xFFE09F3E).withValues(alpha: 0.15)
                    : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                inFolder ? Icons.folder_open_rounded : Icons.shield_outlined,
                size: 34,
                color: inFolder ? const Color(0xFFE09F3E) : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _query.isNotEmpty
                  ? 'No files match "$_query"'
                  : (inFolder ? 'Folder "$_selectedFolder" is empty' : 'Your vault is empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _query.isNotEmpty
                  ? 'Check your spelling or reset the active filters.'
                  : (inFolder
                      ? 'No files in this folder yet. Tap below to store encrypted files here.'
                      : 'Import photos or files to store them with zero-knowledge AES-256 encryption.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (_query.isEmpty) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.add_rounded),
                label: Text(inFolder ? 'Add files to $_selectedFolder' : 'Add files'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFoldersSection(
    BuildContext context,
    List<String> folders,
    List<VaultFile> allFiles,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 17,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Folders',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${folders.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: _createFolder,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 16, color: colors.primary),
                        const SizedBox(width: 3),
                        Text(
                          'New folder',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _folderCard(
                  title: 'All Files',
                  count: allFiles.length,
                  isSelected: _selectedFolder == null,
                  icon: Icons.inventory_2_rounded,
                  iconColor: colors.primary,
                  onTap: () => setState(() => _selectedFolder = null),
                ),
                const SizedBox(width: 10),
                ...folders.map((folder) {
                  final count = allFiles.where((f) => f.folderName == folder).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _folderCard(
                      title: folder,
                      count: count,
                      isSelected: _selectedFolder == folder,
                      icon: Icons.folder_rounded,
                      iconColor: const Color(0xFFE09F3E),
                      onTap: () => setState(() => _selectedFolder = folder),
                      onLongPress: () => _showFolderOptions(folder),
                    ),
                  );
                }),
                _addFolderCard(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderCard({
    required String title,
    required int count,
    required bool isSelected,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 132,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primaryContainer.withValues(alpha: 0.65)
                : colors.surfaceContainerHighest.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 1.6 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const Spacer(),
                  if (onLongPress != null)
                    GestureDetector(
                      onTap: onLongPress,
                      child: Icon(
                        Icons.more_vert_rounded,
                        size: 16,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? colors.onPrimaryContainer : colors.onSurface,
                ),
              ),
              Text(
                '$count ${count == 1 ? 'file' : 'files'}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? colors.onPrimaryContainer.withValues(alpha: 0.8)
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addFolderCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _createFolder,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.create_new_folder_outlined, size: 20, color: colors.primary),
              const SizedBox(height: 4),
              Text(
                '+ New',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFolderBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_open_rounded, size: 17, color: Color(0xFFE09F3E)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Showing: $_selectedFolder',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _selectedFolder = null),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: colors.onPrimaryContainer,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileCard(BuildContext context, VaultFile file) {
    final theme = Theme.of(context);
    final nameLower = file.name.toLowerCase();
    final isImage = file.mimeType.startsWith('image/') ||
        nameLower.endsWith('.jpg') ||
        nameLower.endsWith('.jpeg') ||
        nameLower.endsWith('.png') ||
        nameLower.endsWith('.webp');
    final isPdf = file.mimeType == 'application/pdf' || nameLower.endsWith('.pdf');
    final isDoc = file.mimeType.contains('document') ||
        nameLower.endsWith('.doc') ||
        nameLower.endsWith('.docx') ||
        nameLower.endsWith('.txt');

    final (iconData, iconColor, bgColor) = isImage
        ? (Icons.image_rounded, const Color(0xFFF59E0B), const Color(0xFFFEF3C7))
        : isPdf
            ? (Icons.picture_as_pdf_rounded, const Color(0xFFEF4444), const Color(0xFFFEE2E2))
            : isDoc
                ? (Icons.description_rounded, const Color(0xFF3B82F6), const Color(0xFFDBEAFE))
                : (Icons.insert_drive_file_rounded, const Color(0xFF6B7280), const Color(0xFFF3F4F6));

    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FilePreviewScreen(vault: widget.vault, file: file),
          ),
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? iconColor.withValues(alpha: 0.16) : bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(iconData, color: iconColor, size: 24),
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                _size(file.size),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (file.folderName != null) ...[
                Text(
                  ' · ${file.folderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
              const Spacer(),
              _syncStatus(context, file),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'File actions',
          icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurfaceVariant),
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
                    Text('Sync to cloud'),
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
              child: Text('Move to Recycle Bin', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _syncStatus(BuildContext context, VaultFile file) {
    final (icon, color) = switch (file.syncState) {
      'synced' => (Icons.cloud_done_rounded, Colors.green),
      'uploading' => (Icons.cloud_upload_rounded, Colors.blue),
      'failed' || 'conflict' => (Icons.warning_amber_rounded, Colors.orange),
      'queued' || 'rename_pending' when _hasCloudSession => (Icons.cloud_queue_rounded, Colors.blueGrey),
      _ => (Icons.lock_outline_rounded, Colors.grey),
    };
    return Icon(icon, size: 16, color: color);
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
