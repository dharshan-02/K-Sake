class VaultCredential {
  const VaultCredential({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    this.url,
    this.notes,
    this.category = 'Login',
    this.isHidden = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String username;
  final String password;
  final String? url;
  final String? notes;
  final String category;
  final bool isHidden;
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultCredential copyWith({
    String? id,
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? category,
    bool? isHidden,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      VaultCredential(
        id: id ?? this.id,
        title: title ?? this.title,
        username: username ?? this.username,
        password: password ?? this.password,
        url: url ?? this.url,
        notes: notes ?? this.notes,
        category: category ?? this.category,
        isHidden: isHidden ?? this.isHidden,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
