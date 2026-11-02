import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/local_vault.dart';
import '../models/vault_file.dart';
import 'file_preview_screen.dart';

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
  List<VaultFile> _mediaFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() => _loading = true);
    final files = await widget.vault.listFiles(isHidden: widget.isHiddenVault);
    if (mounted) {
      setState(() {
        _mediaFiles = files.where((f) => f.mimeType.startsWith('image/') || f.mimeType.startsWith('video/')).toList();
        _loading = false;
      });
    }
  }

  Future<void> _importMedia() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'mkv', 'avi'],
    );
    if (result.isEmpty) return;

    var count = 0;
    for (final file in result) {
      final source = file.path;
      if (source == null || !await File(source).exists()) continue;
      final ext = file.extension?.toLowerCase() ?? '';
      final mime = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        _ => 'image/jpeg',
      };
      await widget.vault.importFile(
        source,
        file.name,
        mime,
        isHidden: widget.isHiddenVault,
      );
      count++;
    }

    await _loadMedia();
    if (mounted && count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count media file${count == 1 ? '' : 's'} encrypted into gallery.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mediaFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 64, color: theme.hintColor),
                      const SizedBox(height: 12),
                      Text('No encrypted media yet', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      const Text('Import private photos and videos into your secure safe.'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMedia,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemCount: _mediaFiles.length,
                    itemBuilder: (context, i) {
                      final file = _mediaFiles[i];
                      return _buildMediaTile(file);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importMedia,
        icon: const Icon(Icons.add_photo_alternate),
        label: const Text('Add Media'),
      ),
    );
  }

  Widget _buildMediaTile(VaultFile file) {
    final theme = Theme.of(context);
    final isVideo = file.mimeType.startsWith('video/');

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FilePreviewScreen(vault: widget.vault, file: file),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              isVideo ? Icons.videocam : Icons.image,
              size: 36,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                ),
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
            if (isVideo)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.play_circle_fill, size: 18, color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}

