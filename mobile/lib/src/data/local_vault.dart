import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../models/vault_file.dart';
import '../models/vault_note.dart';
import '../models/vault_credential.dart';

class LocalVault {
  static const _secureStore = FlutterSecureStorage();
  static const _keyName = 'vault_db_key_v1';
  final _uuid = const Uuid();
  final _aead = AesGcm.with256bits();
  Database? _db;
  late Directory _root;
  late SecretKey _vaultSecret;

  Future<void> initialize() async {
    _root = await getApplicationSupportDirectory();
    final temp = await getTemporaryDirectory();
    await for (final entry in temp.list()) {
      if (entry is File &&
          p.basename(entry.path).startsWith('keepsake-preview-')) {
        await entry.delete().catchError((_) => entry);
      }
    }
    final files = Directory(p.join(_root.path, 'vault_files'));
    await files.create(recursive: true);
    var key = await _secureStore.read(key: _keyName);
    if (key == null) {
      key = base64UrlEncode(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await _secureStore.write(key: _keyName, value: key);
    }
    final master = SecretKey(base64Url.decode(base64Url.normalize(key)));
    final kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    _vaultSecret = await kdf.deriveKey(
      secretKey: master,
      nonce: const [],
      info: utf8.encode('keepsake/file-key-wrap/v1'),
    );
    final dbKey = await kdf.deriveKey(
      secretKey: master,
      nonce: const [],
      info: utf8.encode('keepsake/sqlcipher/v1'),
    );
    final keyBytes = await dbKey.extractBytes();
    final dbFile = File(p.join(_root.path, 'vault.sqlite'));
    final db = sqlite3.open(dbFile.path);
    final dbKeyHex = keyBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    db.execute("PRAGMA key = \"x'$dbKeyHex'\"");
    db.execute('PRAGMA cipher_compatibility = 4');
    db.execute('PRAGMA journal_mode = DELETE');
    db.execute('''CREATE TABLE IF NOT EXISTS files (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, mime_type TEXT NOT NULL,
      size INTEGER NOT NULL, created_at TEXT NOT NULL, local_path TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'local', folder_name TEXT
    )''');
    final columns = db
        .select('PRAGMA table_info(files)')
        .map((r) => r['name'] as String)
        .toSet();
    if (!columns.contains('folder_name')) {
      db.execute('ALTER TABLE files ADD COLUMN folder_name TEXT');
    }
    if (!columns.contains('remote_updated_at')) {
      db.execute('ALTER TABLE files ADD COLUMN remote_updated_at TEXT');
    }
    if (!columns.contains('is_hidden')) {
      db.execute('ALTER TABLE files ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0');
    }
    db.execute('''CREATE TABLE IF NOT EXISTS notes (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      color_value INTEGER NOT NULL DEFAULT 4281284424,
      is_pinned INTEGER NOT NULL DEFAULT 0,
      is_hidden INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    db.execute('''CREATE TABLE IF NOT EXISTS credentials (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      username TEXT NOT NULL,
      password TEXT NOT NULL,
      url TEXT,
      notes TEXT,
      category TEXT NOT NULL DEFAULT 'Login',
      is_hidden INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    db.execute(
      'CREATE TABLE IF NOT EXISTS pending_deletes (id TEXT PRIMARY KEY)',
    );
    _db = db;
  }

  Future<List<VaultFile>> listFiles({bool isHidden = false}) async {
    final rows = _db!.select(
      'SELECT * FROM files WHERE is_hidden = ? ORDER BY created_at DESC',
      [isHidden ? 1 : 0],
    );
    return rows
        .map(
          (r) => VaultFile(
            id: r['id'] as String,
            name: r['name'] as String,
            mimeType: r['mime_type'] as String,
            size: r['size'] as int,
            createdAt: DateTime.parse(r['created_at'] as String),
            localPath: r['local_path'] as String,
            syncState: r['sync_state'] as String,
            folderName: r['folder_name'] as String?,
            remoteUpdatedAt: r['remote_updated_at'] == null
                ? null
                : DateTime.parse(r['remote_updated_at'] as String),
            isHidden: (r['is_hidden'] as int? ?? 0) == 1,
          ),
        )
        .toList();
  }

  Future<VaultFile> importFile(
    String sourcePath,
    String name,
    String mimeType, {
    bool isHidden = false,
  }) async {
    final id = _uuid.v4();
    final source = File(sourcePath);
    final destination = File(p.join(_root.path, 'vault_files', '$id.enc'));
    final fileKey = await _aead.newSecretKey();
    const chunkSize = 1024 * 1024;
    final noncePrefix = Uint8List.fromList(
      List<int>.generate(8, (_) => Random.secure().nextInt(256)),
    );
    final keyBytes = await fileKey.extractBytes();
    final wrapped = await _aead.encrypt(
      keyBytes,
      secretKey: _vaultKey(),
      nonce: _aead.newNonce(),
    );
    final header = utf8.encode(
      jsonEncode({
        'v': 1,
        'keyNonce': base64UrlEncode(wrapped.nonce),
        'wrappedKey': base64UrlEncode(wrapped.cipherText),
        'wrappedKeyMac': base64UrlEncode(wrapped.mac.bytes),
        'noncePrefix': base64UrlEncode(noncePrefix),
        'plainSize': await source.length(),
        'chunkSize': chunkSize,
      }),
    );
    final output = await destination.open(mode: FileMode.write);
    final input = await source.open();
    var encryptedSize = 8 + header.length;
    var chunkIndex = 0;
    try {
      await output.writeFrom(const [0x4b, 0x53, 0x56, 0x31]); // KSV1
      final headerLength = ByteData(4)..setUint32(0, header.length, Endian.big);
      await output.writeFrom(headerLength.buffer.asUint8List());
      await output.writeFrom(header);
      while (true) {
        final clearChunk = await input.read(chunkSize);
        if (clearChunk.isEmpty) break;
        if (chunkIndex > 0xffffffff) {
          throw StateError('File exceeds the supported encrypted size');
        }
        final nonce = Uint8List(12)..setRange(0, 8, noncePrefix);
        ByteData.sublistView(nonce).setUint32(8, chunkIndex++, Endian.big);
        final box = await _aead.encrypt(
          clearChunk,
          secretKey: fileKey,
          nonce: nonce,
        );
        final frameLength = ByteData(4)
          ..setUint32(0, box.cipherText.length, Endian.big);
        await output.writeFrom(frameLength.buffer.asUint8List());
        await output.writeFrom(box.nonce);
        await output.writeFrom(box.mac.bytes);
        await output.writeFrom(box.cipherText);
        encryptedSize += 32 + box.cipherText.length;
      }
      await output.flush();
    } finally {
      await input.close();
      await output.close();
    }
    final now = DateTime.now().toUtc();
    _db!.execute(
      'INSERT INTO files (id,name,mime_type,size,created_at,local_path,sync_state,folder_name,is_hidden) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        id,
        name,
        mimeType,
        encryptedSize,
        now.toIso8601String(),
        destination.path,
        'queued',
        null,
        isHidden ? 1 : 0,
      ],
    );
    return VaultFile(
      id: id,
      name: name,
      mimeType: mimeType,
      size: encryptedSize,
      createdAt: now,
      localPath: destination.path,
      syncState: 'queued',
      isHidden: isHidden,
    );
  }

  Future<void> setSyncState(String id, String state) async {
    _db!.execute('UPDATE files SET sync_state = ? WHERE id = ?', [state, id]);
  }

  Future<void> markSynced(String id, DateTime remoteUpdatedAt) async {
    _db!.execute(
      'UPDATE files SET sync_state = ?, remote_updated_at = ? WHERE id = ?',
      ['synced', remoteUpdatedAt.toUtc().toIso8601String(), id],
    );
  }

  Future<void> renameFile(VaultFile file, String newName) async {
    final state = file.syncState == 'synced'
        ? 'rename_pending'
        : file.syncState;
    _db!.execute('UPDATE files SET name = ?, sync_state = ? WHERE id = ?', [
      newName,
      state,
      file.id,
    ]);
  }

  List<String> listFolders({bool isHidden = false}) => _db!
      .select(
        "SELECT DISTINCT folder_name FROM files WHERE is_hidden = ? AND folder_name IS NOT NULL AND folder_name != '' ORDER BY folder_name",
        [isHidden ? 1 : 0],
      )
      .map((r) => r['folder_name'] as String)
      .toList();

  Future<void> setFolder(String id, String? folder) async {
    _db!.execute('UPDATE files SET folder_name = ? WHERE id = ?', [folder, id]);
  }

  Future<VaultFile?> findFile(String id) async {
    final rows = _db!.select('SELECT * FROM files WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return VaultFile(
      id: r['id'] as String,
      name: r['name'] as String,
      mimeType: r['mime_type'] as String,
      size: r['size'] as int,
      createdAt: DateTime.parse(r['created_at'] as String),
      localPath: r['local_path'] as String,
      syncState: r['sync_state'] as String,
      folderName: r['folder_name'] as String?,
      remoteUpdatedAt: r['remote_updated_at'] == null
          ? null
          : DateTime.parse(r['remote_updated_at'] as String),
      isHidden: (r['is_hidden'] as int? ?? 0) == 1,
    );
  }

  Future<void> addDownloadedCiphertext({
    required String id,
    required String name,
    required String mimeType,
    required int size,
    required DateTime createdAt,
    required DateTime remoteUpdatedAt,
    required String sourcePath,
  }) async {
    if (await findFile(id) != null) return;
    final destination = File(p.join(_root.path, 'vault_files', '$id.enc'));
    await File(sourcePath).copy(destination.path);
    _db!.execute(
      'INSERT INTO files (id,name,mime_type,size,created_at,local_path,sync_state,folder_name,remote_updated_at,is_hidden) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        name,
        mimeType,
        size,
        createdAt.toUtc().toIso8601String(),
        destination.path,
        'synced',
        null,
        remoteUpdatedAt.toUtc().toIso8601String(),
        0,
      ],
    );
  }

  // --- Notes CRUD ---
  Future<List<VaultNote>> listNotes({bool isHidden = false}) async {
    final rows = _db!.select(
      'SELECT * FROM notes WHERE is_hidden = ? ORDER BY is_pinned DESC, updated_at DESC',
      [isHidden ? 1 : 0],
    );
    return rows
        .map(
          (r) => VaultNote(
            id: r['id'] as String,
            title: r['title'] as String,
            content: r['content'] as String,
            colorValue: r['color_value'] as int,
            isPinned: (r['is_pinned'] as int) == 1,
            isHidden: (r['is_hidden'] as int) == 1,
            createdAt: DateTime.parse(r['created_at'] as String),
            updatedAt: DateTime.parse(r['updated_at'] as String),
          ),
        )
        .toList();
  }

  Future<VaultNote> saveNote(VaultNote note) async {
    _db!.execute(
      '''INSERT INTO notes (id, title, content, color_value, is_pinned, is_hidden, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           content = excluded.content,
           color_value = excluded.color_value,
           is_pinned = excluded.is_pinned,
           is_hidden = excluded.is_hidden,
           updated_at = excluded.updated_at''',
      [
        note.id,
        note.title,
        note.content,
        note.colorValue,
        note.isPinned ? 1 : 0,
        note.isHidden ? 1 : 0,
        note.createdAt.toIso8601String(),
        note.updatedAt.toIso8601String(),
      ],
    );
    return note;
  }

  Future<void> deleteNote(String id) async {
    _db!.execute('DELETE FROM notes WHERE id = ?', [id]);
  }

  // --- Credentials & Passwords CRUD ---
  Future<List<VaultCredential>> listCredentials({bool isHidden = false}) async {
    final rows = _db!.select(
      'SELECT * FROM credentials WHERE is_hidden = ? ORDER BY title ASC',
      [isHidden ? 1 : 0],
    );
    return rows
        .map(
          (r) => VaultCredential(
            id: r['id'] as String,
            title: r['title'] as String,
            username: r['username'] as String,
            password: r['password'] as String,
            url: r['url'] as String?,
            notes: r['notes'] as String?,
            category: r['category'] as String,
            isHidden: (r['is_hidden'] as int) == 1,
            createdAt: DateTime.parse(r['created_at'] as String),
            updatedAt: DateTime.parse(r['updated_at'] as String),
          ),
        )
        .toList();
  }

  Future<VaultCredential> saveCredential(VaultCredential cred) async {
    _db!.execute(
      '''INSERT INTO credentials (id, title, username, password, url, notes, category, is_hidden, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           username = excluded.username,
           password = excluded.password,
           url = excluded.url,
           notes = excluded.notes,
           category = excluded.category,
           is_hidden = excluded.is_hidden,
           updated_at = excluded.updated_at''',
      [
        cred.id,
        cred.title,
        cred.username,
        cred.password,
        cred.url,
        cred.notes,
        cred.category,
        cred.isHidden ? 1 : 0,
        cred.createdAt.toIso8601String(),
        cred.updatedAt.toIso8601String(),
      ],
    );
    return cred;
  }

  Future<void> deleteCredential(String id) async {
    _db!.execute('DELETE FROM credentials WHERE id = ?', [id]);
  }

  Future<void> toggleFileHidden(String id, bool isHidden) async {
    _db!.execute('UPDATE files SET is_hidden = ? WHERE id = ?', [
      isHidden ? 1 : 0,
      id,
    ]);
  }

  Future<void> clearPreviewCache() async {
    final temp = await getTemporaryDirectory();
    await for (final entry in temp.list()) {
      if (entry is File &&
          p.basename(entry.path).startsWith('keepsake-preview-')) {
        await entry.delete().catchError((_) => entry);
      }
    }
  }

  Future<Map<String, dynamic>> getVaultStats({bool isHidden = false}) async {
    final fileRows = _db!.select(
      'SELECT COUNT(*) as count, COALESCE(SUM(size), 0) as total_size FROM files WHERE is_hidden = ?',
      [isHidden ? 1 : 0],
    );
    final noteRows = _db!.select(
      'SELECT COUNT(*) as count FROM notes WHERE is_hidden = ?',
      [isHidden ? 1 : 0],
    );
    final credRows = _db!.select(
      'SELECT COUNT(*) as count FROM credentials WHERE is_hidden = ?',
      [isHidden ? 1 : 0],
    );
    return {
      'fileCount': fileRows.first['count'] as int,
      'totalBytes': fileRows.first['total_size'] as int,
      'noteCount': noteRows.first['count'] as int,
      'credentialCount': credRows.first['count'] as int,
    };
  }
        null,
        remoteUpdatedAt.toUtc().toIso8601String(),
      ],
    );
  }

  Future<File> decryptToTemporaryFile(VaultFile file) async {
    final input = await File(file.localPath).open();
    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(file.name).replaceAll(RegExp(r'[^.a-zA-Z0-9]'), '');
    final outputFile = File(
      p.join(tempDir.path, 'keepsake-preview-${_uuid.v4()}$ext'),
    );
    final output = await outputFile.open(mode: FileMode.write);
    var succeeded = false;
    try {
      final magic = await _readExactly(input, 4);
      if (utf8.decode(magic) != 'KSV1') {
        throw const FormatException('Unknown encrypted file format');
      }
      final headerSizeBytes = Uint8List.fromList(await _readExactly(input, 4));
      final headerSize = ByteData.sublistView(headerSizeBytes)
          .getUint32(0, Endian.big);
      if (headerSize > 64 * 1024) {
        throw const FormatException('Encrypted file header is too large');
      }
      final header = jsonDecode(
        utf8.decode(await _readExactly(input, headerSize)),
      ) as Map<String, dynamic>;
      if (header['v'] != 1) {
        throw const FormatException('Unsupported encrypted file version');
      }
      final wrapped = SecretBox(
        base64Url.decode(header['wrappedKey'] as String),
        nonce: base64Url.decode(header['keyNonce'] as String),
        mac: Mac(base64Url.decode(header['wrappedKeyMac'] as String)),
      );
      final fileKey = SecretKey(
        await _aead.decrypt(wrapped, secretKey: _vaultKey()),
      );
      final prefix = base64Url.decode(header['noncePrefix'] as String);
      if (prefix.length != 8) {
        throw const FormatException('Invalid encrypted file nonce');
      }
      final chunkSize = header['chunkSize'] as int;
      final expectedSize = header['plainSize'] as int;
      if (chunkSize != 1024 * 1024 || expectedSize < 0) {
        throw const FormatException('Invalid encrypted file header');
      }
      var written = 0;
      var index = 0;
      while (written < expectedSize) {
        final frameSizeBytes = Uint8List.fromList(await _readExactly(input, 4));
        final frameSize = ByteData.sublistView(frameSizeBytes)
            .getUint32(0, Endian.big);
        if (frameSize == 0 ||
            frameSize > chunkSize ||
            written + frameSize > expectedSize) {
          throw const FormatException('Invalid encrypted file chunk');
        }
        final nonce = Uint8List.fromList(await _readExactly(input, 12));
        if (!nonce
                .sublist(0, 8)
                .asMap()
                .entries
                .every((e) => e.value == prefix[e.key]) ||
            ByteData.sublistView(nonce).getUint32(8, Endian.big) != index++) {
          throw const FormatException(
            'Encrypted file chunk sequence is invalid',
          );
        }
        final mac = Mac(await _readExactly(input, 16));
        final cipherText = await _readExactly(input, frameSize);
        final clear = await _aead.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: mac),
          secretKey: fileKey,
        );
        await output.writeFrom(clear);
        written += clear.length;
      }
      if (await input.length() != await input.position()) {
        throw const FormatException('Unexpected encrypted file data');
      }
      await output.flush();
      succeeded = true;
      return outputFile;
    } finally {
      await input.close();
      await output.close();
      if (!succeeded && await outputFile.exists()) await outputFile.delete();
    }
  }

  Future<List<int>> _readExactly(RandomAccessFile file, int length) async {
    final bytes = await file.read(length);
    if (bytes.length != length) {
      throw const FormatException('Encrypted file is truncated');
    }
    return bytes;
  }

  List<String> pendingDeletes() => _db!
      .select('SELECT id FROM pending_deletes')
      .map((r) => r['id'] as String)
      .toList();

  Future<String> masterKeyForRecovery() async {
    final key = await _secureStore.read(key: _keyName);
    if (key == null) throw StateError('The local vault key is unavailable.');
    return key;
  }

  Future<void> restoreMasterKey(String encodedKey) async {
    final keyBytes = base64Url.decode(base64Url.normalize(encodedKey));
    if (keyBytes.length != 32) {
      throw const FormatException('Recovery code is invalid.');
    }
    if ((await listFiles()).isNotEmpty) {
      throw StateError(
        'This device already has local files. Export them before replacing its vault key.',
      );
    }
    final dbPath = p.join(_root.path, 'vault.sqlite');
    _db?.close();
    _db = null;
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$dbPath$suffix');
      if (await file.exists()) await file.delete();
    }
    await _secureStore.write(key: _keyName, value: base64UrlEncode(keyBytes));
    await initialize();
  }

  Future<void> completeDelete(String id) async {
    _db!.execute('DELETE FROM pending_deletes WHERE id = ?', [id]);
  }

  Future<void> deleteFile(VaultFile file) async {
    final path = p.normalize(file.localPath);
    final filesRoot =
        '${p.normalize(p.join(_root.path, 'vault_files'))}${p.separator}';
    if (p.isAbsolute(path) && path.startsWith(filesRoot)) {
      final local = File(path);
      if (await local.exists()) await local.delete();
    }
    if (file.remoteUpdatedAt != null) {
      _db!.execute('INSERT OR IGNORE INTO pending_deletes (id) VALUES (?)', [
        file.id,
      ]);
    }
    _db!.execute('DELETE FROM files WHERE id = ?', [file.id]);
  }

  SecretKey _vaultKey() {
    return _vaultSecret;
  }
}
