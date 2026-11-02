class VaultNote {
  const VaultNote({
    required this.id,
    required this.title,
    required this.content,
    this.colorValue = 0xFF2D3748,
    this.isPinned = false,
    this.isHidden = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final int colorValue;
  final bool isPinned;
  final bool isHidden;
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultNote copyWith({
    String? id,
    String? title,
    String? content,
    int? colorValue,
    bool? isPinned,
    bool? isHidden,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      VaultNote(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        colorValue: colorValue ?? this.colorValue,
        isPinned: isPinned ?? this.isPinned,
        isHidden: isHidden ?? this.isHidden,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
