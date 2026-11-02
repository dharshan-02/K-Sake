import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

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
