import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/firebase_sync_service.dart';
import '../data/local_vault.dart';
import '../models/vault_file.dart';
import 'file_preview_screen.dart';
import 'recycle_bin_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.vault,
    this.isHiddenVault = false,
  });
  final LocalVault vault;
  final bool isHiddenVault;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late final ApiClient _api = ApiClient(widget.vault);
  late final FirebaseSyncService _firebaseSync = FirebaseSyncService(widget.vault);
  List<VaultFile> _mediaFiles = [];
  List<Map<String, dynamic>> _cloudMedia = [];
  final Set<String> _busyIds = {};
  final Map<String, double> _uploadProgress = {};
  bool _loading = true;
  bool _showCloud = false;
  bool _hasCloudSession = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  bool _isMedia(String mime, String name) {
    final ext = name.toLowerCase().split('.').last;
    return mime.toLowerCase().startsWith('image/') ||
        mime.toLowerCase().startsWith('video/') ||
        {
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'heic',
          'mp4',
          'mov',
          'mkv',
          'avi',
          '3gp',
        }.contains(ext);
  }

  Future<void> _loadMedia() async {
    if (mounted) setState(() => _loading = true);
    try {
      final isCloud = _firebaseSync.isAuthenticated || await _api.hasSession;
      _hasCloudSession = !widget.isHiddenVault && isCloud;
      if (_showCloud && !widget.isHiddenVault) {
        if (!_hasCloudSession) {
          _cloudMedia = [];
          _message = 'Sign in with an account to view and sync cloud media.';
        } else {
          final files = _firebaseSync.isAuthenticated
              ? await _firebaseSync.listCloudFiles()
              : await _api.listCloudFiles();
          _cloudMedia = files
              .where(
                (file) => _isMedia(
                  file['mimeType'] as String? ?? '',
                  file['name'] as String? ?? '',
                ),
              )
              .toList();
          _message = null;
        }
      } else {
        final files = await widget.vault.listFiles(
          isHidden: widget.isHiddenVault,
        );
        _mediaFiles = files
            .where((file) => _isMedia(file.mimeType, file.name))
            .toList();
        _message = null;
      }
    } catch (error) {
      _message = error.toString().replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importMedia() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'heic',
          'mp4',
          'mov',
          'mkv',
          'avi',
          '3gp',
        ],
      );
      if (result.isEmpty) return;
      var count = 0;
      for (final file in result) {
        final source = file.path;
        if (source == null || !await File(source).exists()) continue;
        final ext = (file.extension ?? file.name.split('.').last).toLowerCase();
        final mime = switch (ext) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          'gif' => 'image/gif',
          'webp' => 'image/webp',
          'heic' => 'image/heic',
          'mp4' => 'video/mp4',
          'mov' => 'video/quicktime',
          'mkv' => 'video/x-matroska',
          'avi' => 'video/x-msvideo',
          '3gp' => 'video/3gpp',
          _ => 'application/octet-stream',
        };
        await widget.vault.importFile(
          source,
          file.name,
          mime,
          isHidden: widget.isHiddenVault,
        );
        count++;
      }
      if (count == 0) {
        throw StateError('No selected media files could be read.');
      }
      await widget.vault.addNotification(
        'Media added',
        '$count photo${count == 1 ? '' : 's or videos'} encrypted on this device.',
        isHidden: widget.isHiddenVault,
      );
      var syncNote = '';
      if (!widget.isHiddenVault && (_firebaseSync.isAuthenticated || await _api.hasSession)) {
        try {
          final int uploadedCount;
          if (_firebaseSync.isAuthenticated) {
            final res = await _firebaseSync.syncAll(downloadMissing: false);
            uploadedCount = res.uploaded;
          } else {
            final res = await _api.syncAll(downloadMissing: false);
            uploadedCount = res.uploaded;
          }
          syncNote = uploadedCount > 0
              ? ' $uploadedCount uploaded.'
              : ' Check each file’s status for sync details.';
          if (uploadedCount > 0) {
            await widget.vault.addNotification(
              'Gallery uploads complete',
              '$uploadedCount media file${uploadedCount == 1 ? '' : 's'} synced.',
              type: 'upload',
            );
          }
        } catch (_) {
          syncNote = ' Upload them later when you are connected.';
        }
      }
      await _loadMedia();
      if (mounted) {
        setState(
          () => _message =
              '$count media file${count == 1 ? '' : 's'} encrypted on this device.$syncNote',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> _upload(VaultFile file) async {
    if (widget.isHiddenVault || _busyIds.contains(file.id)) return;
    setState(() {
      _busyIds.add(file.id);
      _message = null;
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
        );
      }
      await widget.vault.addNotification(
        'Gallery upload complete',
        file.name,
        type: 'upload',
      );
      if (mounted) setState(() => _message = '“${file.name}” synced.');
    } catch (error) {
      await widget.vault.addNotification(
        'Gallery upload needs attention',
        file.name,
        type: 'error',
      );
      if (mounted) {
        setState(
          () => _message = 'Upload failed. The encrypted media stays on this device. Retry when online.',
        );
      }
    } finally {
      _uploadProgress.remove(file.id);
      if (mounted) {
        setState(() => _busyIds.remove(file.id));
        await _loadMedia();
      }
    }
  }

  Future<void> _download(Map<String, dynamic> file) async {
    final id = file['id'] as String;
    if (_busyIds.contains(id)) return;
    setState(() {
      _busyIds.add(id);
      _message = null;
    });
    try {
      if (_firebaseSync.isAuthenticated) {
        await _firebaseSync.downloadToVault(file);
      } else {
        await _api.downloadToVault(file);
      }
      await widget.vault.addNotification(
        'Media downloaded',
        file['name'] as String,
        type: 'download',
      );
      await _loadMedia();
      if (mounted) {
        setState(() => _message = '“${file['name']}” is available offline.');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'Download failed. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _delete(VaultFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move media to Recycle Bin?'),
        content: Text(
          '“${file.name}” can be restored from the Recycle Bin until you permanently delete it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to Recycle Bin'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.vault.deleteFile(file);
    await widget.vault.addNotification(
      'Media moved to Recycle Bin',
      file.name,
      type: 'trash',
      isHidden: widget.isHiddenVault,
    );
    await _loadMedia();
  }

  @override
  Widget build(BuildContext context) {
    final mediaCount = _showCloud ? _cloudMedia.length : _mediaFiles.length;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _showCloud
                        ? 'Cloud photos and videos'
                        : 'Photos and videos',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!_showCloud)
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
                        .then((_) => _loadMedia()),
                    tooltip: 'Open Recycle Bin',
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
          if (!widget.isHiddenVault)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('On this device'),
                    icon: Icon(Icons.phone_android_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Cloud'),
                    icon: Icon(Icons.cloud_outlined),
                  ),
                ],
                selected: {_showCloud},
                onSelectionChanged: (selection) async {
                  setState(() => _showCloud = selection.first);
                  await _loadMedia();
                },
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : mediaCount == 0
                ? RefreshIndicator(
                    onRefresh: _loadMedia,
                    child: ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * .2,
                        ),
                        Icon(
                          Icons.photo_library_outlined,
                          size: 56,
                          color: Theme.of(context).hintColor,
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            _message ??
                                (_showCloud
                                    ? 'No photos or videos in cloud.'
                                    : 'No encrypted media yet.'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Center(
                          child: Text(
                            'Add photos and videos to keep them private.',
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadMedia,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: mediaCount,
                      itemBuilder: (context, index) => _showCloud
                          ? _cloudTile(_cloudMedia[index])
                          : _localTile(_mediaFiles[index]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _showCloud
          ? null
          : FloatingActionButton.extended(
              onPressed: _importMedia,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add media'),
            ),
    );
  }

  Widget _localTile(VaultFile file) {
    final isVideo = file.mimeType.startsWith('video/');
    return _tileBase(
      title: file.name,
      icon: isVideo ? Icons.videocam_outlined : Icons.image_outlined,
      status: _busyIds.contains(file.id) && _uploadProgress.containsKey(file.id)
          ? 'Uploading ${((_uploadProgress[file.id] ?? 0) * 100).round()}%'
          : switch (file.syncState) {
              'synced' => 'Synced',
              'uploading' => 'Uploading…',
              'failed' || 'conflict' => 'Needs attention',
              'queued' || 'rename_pending' when _hasCloudSession => 'Queued',
              _ => 'On this device',
            },
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FilePreviewScreen(vault: widget.vault, file: file),
        ),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Media actions',
        onSelected: (action) {
          if (action == 'delete') _delete(file);
          if (action == 'upload') _upload(file);
        },
        itemBuilder: (_) => [
          if (!widget.isHiddenVault && file.syncState != 'synced')
            const PopupMenuItem(
              value: 'upload',
              child: Text('Upload or retry'),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Move to Recycle Bin'),
          ),
        ],
      ),
      deleteButton: IconButton.filled(
        onPressed: () => _delete(file),
        tooltip: 'Move to Recycle Bin',
        style: IconButton.styleFrom(
          backgroundColor: Colors.black54,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }

  Widget _cloudTile(Map<String, dynamic> file) {
    final id = file['id'] as String;
    final name = file['name'] as String? ?? 'Media file';
    return FutureBuilder<VaultFile?>(
      future: widget.vault.findFile(id),
      builder: (context, snapshot) {
        final local = snapshot.data;
        return _tileBase(
          title: name,
          icon: (file['mimeType'] as String? ?? '').startsWith('video/')
              ? Icons.videocam_outlined
              : Icons.image_outlined,
          status: local == null
              ? (_busyIds.contains(id) ? 'Downloading…' : 'Download')
              : 'Available offline',
          onTap: local == null
              ? () => _download(file)
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        FilePreviewScreen(vault: widget.vault, file: local),
                  ),
                ),
          deleteButton: IconButton.filled(
            onPressed: local == null
                ? () => _download(file)
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          FilePreviewScreen(vault: widget.vault, file: local),
                    ),
                  ),
            tooltip: local == null ? 'Download to device' : 'Open media',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
            icon: Icon(
              local == null
                  ? Icons.download_for_offline_outlined
                  : Icons.open_in_new,
            ),
          ),
        );
      },
    );
  }

  Widget _tileBase({
    required String title,
    required IconData icon,
    required String status,
    required VoidCallback onTap,
    required Widget deleteButton,
    Widget? trailing,
  }) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Center(
            child: Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: trailing ?? const SizedBox.shrink(),
          ),
          Positioned(right: 2, bottom: 26, child: deleteButton),
          Positioned(
            left: 6,
            right: 6,
            bottom: 5,
            child: Column(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
