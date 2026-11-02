class VaultFile {
  const VaultFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    required this.localPath,
    required this.syncState,
    this.folderName,
    this.remoteUpdatedAt,
    this.isHidden = false,
  });

  final String id;
  final String name;
  final String mimeType;
  final int size;
  final DateTime createdAt;
  final String localPath;
  final String syncState;
  final String? folderName;
  final DateTime? remoteUpdatedAt;
  final bool isHidden;
}
