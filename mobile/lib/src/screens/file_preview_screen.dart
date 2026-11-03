import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

import '../data/local_vault.dart';
import '../models/vault_file.dart';

class FilePreviewScreen extends StatefulWidget {
  const FilePreviewScreen({super.key, required this.vault, required this.file});
  final LocalVault vault;
  final VaultFile file;

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  late final Future<File> _plainFile = widget.vault.decryptToTemporaryFile(
    widget.file,
  );

  @override
  void dispose() {
    _plainFile
        .then((file) async {
          if (await file.exists()) await file.delete();
        })
        .catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: FutureBuilder<File>(
      future: _plainFile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('This file could not be decrypted or is damaged.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final file = snapshot.data!;
        final ext = widget.file.name.split('.').last.toLowerCase();
        if (widget.file.mimeType.startsWith('video/') ||
            const {'mp4', 'mov', 'mkv', 'avi', '3gp'}.contains(ext)) {
          return _EncryptedVideoPreview(file: file);
        }
        if (widget.file.mimeType.startsWith('image/') ||
            const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext)) {
          return InteractiveViewer(
            child: Center(child: Image.file(file, fit: BoxFit.contain)),
          );
        }
        if (ext == 'pdf') return PdfViewer.file(file.path);
        if (ext == 'txt' || ext == 'md' || ext == 'csv' || ext == 'json') {
          return FutureBuilder<String>(
            future: file.length().then(
              (n) => n > 1024 * 1024
                  ? 'Text preview is limited to files under 1 MB.'
                  : file.readAsString(),
            ),
            builder: (context, text) => text.hasData
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(text.data!),
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        }
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'This file is encrypted and stored locally. Preview is not available for this format yet.',
            ),
          ),
        );
      },
    ),
  );
}

class _EncryptedVideoPreview extends StatefulWidget {
  const _EncryptedVideoPreview({required this.file});
  final File file;

  @override
  State<_EncryptedVideoPreview> createState() => _EncryptedVideoPreviewState();
}

class _EncryptedVideoPreviewState extends State<_EncryptedVideoPreview> {
  late final VideoPlayerController _controller = VideoPlayerController.file(
    widget.file,
  );
  late final Future<void> _initialized = _controller.initialize();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialized,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('This video format cannot be played on this device.'),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final aspect = _controller.value.aspectRatio;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: aspect > 0 ? aspect : 16 / 9,
                child: VideoPlayer(_controller),
              ),
              Row(
                children: [
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) => IconButton(
                      onPressed: () => value.isPlaying
                          ? _controller.pause()
                          : _controller.play(),
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      tooltip: value.isPlaying ? 'Pause video' : 'Play video',
                    ),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
