import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/vault_file.dart';
import 'local_vault.dart';

class SyncSummary {
  const SyncSummary({
    required this.uploaded,
    required this.downloaded,
    required this.totalCloud,
  });
  final int uploaded;
  final int downloaded;
  final int totalCloud;
}

class ApiConnectionException implements Exception {
  const ApiConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.vault);
  final LocalVault vault;
  static const _storage = FlutterSecureStorage();
  static const _ownerKey = 'vault_account_owner_v1';
  static const _userEmailKey = 'logged_in_user_email_v1';
  static const _serverUrlKey = 'custom_server_url_v1';
  static const _deviceIdKey = 'keepsake_device_id_v1';
  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/v1',
  );

  final _client = http.Client();
  final _aead = AesGcm.with256bits();

  static Future<String> getBaseUrl() async {
    final custom = await _storage.read(key: _serverUrlKey);
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }
    return _defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    await _storage.write(key: _serverUrlKey, value: url.trim());
  }

  Future<Uri> _uri(String path) async {
    final base = await getBaseUrl();
    final cleanBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$cleanBase/$cleanPath');
  }

  Future<void> authenticate(
    String email,
    String password, {
    required bool createAccount,
  }) async {
    final uri = await _uri('auth/${createAccount ? 'register' : 'login'}');
    var deviceId = await _storage.read(key: _deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: deviceId);
    }
    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              'deviceId': deviceId,
              'deviceName':
                  '${Platform.isAndroid
                      ? 'Android phone'
                      : Platform.isIOS
                      ? 'iPhone or iPad'
                      : 'Keepsake device'} · ${deviceId.substring(0, 4).toUpperCase()}',
            }),
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw ApiConnectionException(
        'The Keepsake API did not respond. Start the API and database, then check the server address. On a physical phone, 10.0.2.2 will not work; use your computer’s Wi-Fi IP. Your local files are still available.',
      );
    } on SocketException {
      throw ApiConnectionException(
        'Keepsake could not connect to the API. Check that the API and database are running and the server address is correct. On a physical phone, use your computer’s Wi-Fi IP instead of 10.0.2.2.',
      );
    } on http.ClientException {
      throw ApiConnectionException(
        'Keepsake could not connect to the server. Check your connection and server address, or use the demo/local vault while offline.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String msg = 'Could not sign in. Check your details and try again.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          msg = body['message'].toString();
        }
      } catch (_) {}
      throw Exception(msg);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['accessToken'] as String;
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const FormatException(
        'The server returned an invalid access token.',
      );
    }
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final subject = claims['sub'] as String;
    final linkedAccount = await _storage.read(key: _ownerKey);
    if (linkedAccount != null && linkedAccount != subject) {
      // Clean previous session when logging into another account
      await _storage.delete(key: _ownerKey);
    }
    await _storage.write(key: _ownerKey, value: subject);
    await _storage.write(key: _userEmailKey, value: email.trim().toLowerCase());
    await _storage.write(key: 'account_access_token', value: token);
  }

  Future<bool> get hasSession async =>
      await _storage.read(key: 'account_access_token') != null;
  Future<String?> get userEmail async =>
      await _storage.read(key: _userEmailKey);

  Future<List<Map<String, dynamic>>> getDevices() async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to manage your devices.');
    final response = await _client
        .get(
          await _uri('auth/devices'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiConnectionException(
        response.statusCode == 401
            ? 'Your cloud session expired. Sign in again to manage devices.'
            : 'Could not load your signed-in devices. Check your connection and try again.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException(
        'The server returned an invalid device list.',
      );
    }
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<String?> get currentSessionId async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return claims is Map<String, dynamic> ? claims['sid'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> revokeDevice(String sessionId) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to manage your devices.');
    final response = await _client
        .delete(
          await _uri('auth/devices/${Uri.encodeComponent(sessionId)}'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiConnectionException(
        response.statusCode == 401
            ? 'Your cloud session expired. Sign in again to manage devices.'
            : 'Could not revoke that device. Refresh the list and try again.',
      );
    }
  }

  Future<void> signOut() async {
    final token = await _storage.read(key: 'account_access_token');
    if (token != null) {
      try {
        await _client
            .post(
              await _uri('auth/logout'),
              headers: {'authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Always clear this device's credentials, even when offline. The
        // short-lived server token expires on its own if revocation cannot run.
      }
    }
    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    await _storage.delete(key: 'account_access_token');
    await _storage.delete(key: _ownerKey);
    await _storage.delete(key: _userEmailKey);
  }

  Future<void> deleteAccount(String password) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) {
      throw StateError('Sign in before deleting your account.');
    }
    late final http.Response response;
    try {
      response = await _client
          .delete(
            await _uri('auth/account'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({'password': password}),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ApiConnectionException(
        'The delete request timed out. Check your connection and sign in to confirm whether the account still exists before retrying.',
      );
    } on SocketException {
      throw ApiConnectionException(
        'Keepsake could not reach the server. Your account was not confirmed deleted.',
      );
    } on http.ClientException {
      throw ApiConnectionException(
        'Keepsake could not reach the server. Your account was not confirmed deleted.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'The account could not be deleted. Try again.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          message = body['message'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }
    await clearLocalSession();
  }

  Future<String> createRecoveryCode() async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in before setting up recovery.');
    final codeBytes = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
    );
    final code = _encode(codeBytes);
    final masterBytes = base64Url.decode(
      base64Url.normalize(await vault.masterKeyForRecovery()),
    );
    final box = await _aead.encrypt(
      masterBytes,
      secretKey: SecretKey(codeBytes),
    );
    await _storage.write(key: 'pending_recovery_code_v1', value: code);
    try {
      final uri = await _uri('keys/recovery');
      final response = await _client.put(
        uri,
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'nonce': _encode(box.nonce),
          'ciphertext': _encode([...box.cipherText, ...box.mac.bytes]),
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Recovery setup could not be saved.');
      }
      return code;
    } catch (_) {
      await _storage.delete(key: 'pending_recovery_code_v1');
      rethrow;
    }
  }

  Future<String?> pendingRecoveryCode() =>
      _storage.read(key: 'pending_recovery_code_v1');
  Future<void> acknowledgeRecoveryCode() =>
      _storage.delete(key: 'pending_recovery_code_v1');

  Future<void> restoreWithRecoveryCode(String code) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in before restoring your vault.');
    final codeBytes = base64Url.decode(base64Url.normalize(code.trim()));
    if (codeBytes.length != 32) {
      throw const FormatException(
        'Enter the complete 43-character recovery code.',
      );
    }
    final uri = await _uri('keys/recovery');
    final response = await _client.get(
      uri,
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('No recovery code is set for this account.');
    }
    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    final combined = base64Url.decode(
      base64Url.normalize(envelope['ciphertext'] as String),
    );
    if (combined.length != 48) {
      throw const FormatException('Recovery data is invalid.');
    }
    final box = SecretBox(
      combined.sublist(0, 32),
      nonce: base64Url.decode(base64Url.normalize(envelope['nonce'] as String)),
      mac: Mac(combined.sublist(32)),
    );
    final master = await _aead.decrypt(box, secretKey: SecretKey(codeBytes));
    await vault.restoreMasterKey(_encode(master));
  }

  String _encode(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

  Future<int> syncQueued({
    void Function(String id, int sent, int total)? onUploadProgress,
    bool Function(String id)? isUploadCancelled,
  }) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to sync your vault.');
    var completed = 0;
    for (final id in vault.pendingDeletes()) {
      try {
        final uri = await _uri('files/$id');
        final response = await _client.delete(
          uri,
          headers: {'authorization': 'Bearer $token'},
        );
        if ((response.statusCode >= 200 && response.statusCode < 300) ||
            response.statusCode == 404) {
          await vault.completeDelete(id);
        }
      } catch (_) {
        /* Retry at next sync */
      }
    }
    for (final file in await vault.listFiles()) {
      if (file.syncState == 'synced' || file.syncState == 'conflict') continue;
      await vault.setSyncState(file.id, 'uploading');
      onUploadProgress?.call(file.id, 0, file.size);
      try {
        if (file.syncState == 'rename_pending') {
          if (file.remoteUpdatedAt != null) {
            final uri = await _uri('files/${file.id}');
            final renamed = await _client.patch(
              uri,
              headers: {
                'authorization': 'Bearer $token',
                'content-type': 'application/json',
              },
              body: jsonEncode({
                'name': file.name,
                'expectedUpdatedAt': file.remoteUpdatedAt!
                    .toUtc()
                    .toIso8601String(),
              }),
            );
            if (renamed.statusCode == 409) throw const SyncConflict();
            if (renamed.statusCode < 200 || renamed.statusCode >= 300) {
              throw Exception('Rename sync failed');
            }
            final updatedAt = DateTime.parse(
              (jsonDecode(renamed.body) as Map<String, dynamic>)['updatedAt']
                  as String,
            );
            await vault.markSynced(file.id, updatedAt);
            completed++;
            continue;
          }
          await vault.setSyncState(file.id, 'queued');
        }
        final updatedAt = await _upload(
          token,
          file,
          onProgress: (sent, total) =>
              onUploadProgress?.call(file.id, sent, total),
          isCancelled: () => isUploadCancelled?.call(file.id) ?? false,
        );
        await vault.markSynced(file.id, updatedAt);
        completed++;
      } on SyncConflict {
        await vault.setSyncState(file.id, 'conflict');
      } on UploadCancelled {
        await vault.setSyncState(file.id, 'queued');
      } catch (_) {
        await vault.setSyncState(file.id, 'failed');
      }
    }
    return completed;
  }

  Future<void> uploadSingleFile(
    VaultFile file, {
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to upload files to cloud.');
    await vault.setSyncState(file.id, 'uploading');
    try {
      final updatedAt = await _upload(
        token,
        file,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      await vault.markSynced(file.id, updatedAt);
    } on UploadCancelled {
      await vault.setSyncState(file.id, 'queued');
      rethrow;
    } catch (_) {
      await vault.setSyncState(file.id, 'failed');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listCloudFiles() async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to view your cloud files.');
    final uri = await _uri('files');
    final response = await _client.get(
      uri,
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Cloud files could not be loaded. Sign in again and retry.',
      );
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> downloadToVault(Map<String, dynamic> file) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to download files.');
    final id = file['id'] as String;
    final uri = await _uri('files/$id/download');
    final metadata = await _client.get(
      uri,
      headers: {'authorization': 'Bearer $token'},
    );
    if (metadata.statusCode < 200 || metadata.statusCode >= 300) {
      throw Exception('A download link could not be created.');
    }
    final url =
        (jsonDecode(metadata.body) as Map<String, dynamic>)['downloadUrl']
            as String;
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Encrypted file download failed.');
    }
    final tempDir = await getTemporaryDirectory();
    final temp = File(p.join(tempDir.path, 'keepsake-cloud-$id.tmp'));
    final sink = temp.openWrite();
    try {
      await response.stream.pipe(sink);
      await vault.addDownloadedCiphertext(
        id: id,
        name: file['name'] as String,
        mimeType: file['mimeType'] as String,
        size: (file['size'] as num).toInt(),
        createdAt: DateTime.parse(file['createdAt'] as String),
        remoteUpdatedAt: DateTime.parse(file['updatedAt'] as String),
        sourcePath: temp.path,
      );
    } finally {
      await sink.close();
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<SyncSummary> syncAll({
    bool downloadMissing = true,
    void Function(String id, int sent, int total)? onUploadProgress,
    bool Function(String id)? isUploadCancelled,
  }) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to sync with cloud.');

    final uploadedCount = await syncQueued(
      onUploadProgress: onUploadProgress,
      isUploadCancelled: isUploadCancelled,
    );
    var downloadedCount = 0;
    List<Map<String, dynamic>> cloudFiles = [];

    try {
      cloudFiles = await listCloudFiles();
      if (downloadMissing) {
        final queuedDeletes = vault.pendingDeletes().toSet();
        for (final item in cloudFiles) {
          final id = item['id'] as String;
          if (queuedDeletes.contains(id)) continue;
          final localFile = await vault.findFile(id);
          if (localFile == null) {
            final trashedFile = await vault.findFile(id, includeTrashed: true);
            if (trashedFile != null) continue;
            try {
              await downloadToVault(item);
              downloadedCount++;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return SyncSummary(
      uploaded: uploadedCount,
      downloaded: downloadedCount,
      totalCloud: cloudFiles.length,
    );
  }

  Future<DateTime> _upload(
    String token,
    VaultFile file, {
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final headers = {
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    };
    final uploadUri = await _uri('files/upload');
    final begin = await _client.post(
      uploadUri,
      headers: headers,
      body: jsonEncode({
        'id': file.id,
        'name': file.name,
        'mimeType': 'application/octet-stream',
        'size': file.size,
      }),
    );
    if (begin.statusCode < 200 || begin.statusCode >= 300) {
      throw Exception('Upload could not be started');
    }
    final payload = jsonDecode(begin.body) as Map<String, dynamic>;
    if (payload['alreadyUploaded'] == true) {
      return DateTime.parse(payload['updatedAt'] as String);
    }
    final request = http.StreamedRequest(
      'PUT',
      Uri.parse(payload['uploadUrl'] as String),
    );
    request.headers['content-type'] = 'application/octet-stream';
    final local = File(file.localPath);
    request.contentLength = await local.length();
    final sendFuture = _client.send(request);
    var sentBytes = 0;
    var requestClosed = false;
    Future<void> closeRequest() async {
      if (requestClosed) return;
      requestClosed = true;
      await request.sink.close();
    }

    try {
      await for (final chunk in local.openRead()) {
        if (isCancelled?.call() ?? false) {
          await closeRequest();
          try {
            await sendFuture;
          } catch (_) {
            // Consume the failed response from the intentionally truncated upload.
          }
          throw const UploadCancelled();
        }
        request.sink.add(chunk);
        sentBytes += chunk.length;
        onProgress?.call(sentBytes, request.contentLength!);
      }
      await closeRequest();
    } catch (_) {
      await closeRequest();
      rethrow;
    }
    final response = await sendFuture;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Encrypted file upload failed');
    }
    final completeUri = await _uri('files/${file.id}/complete');
    final complete = await _client.post(completeUri, headers: headers);
    if (complete.statusCode < 200 || complete.statusCode >= 300) {
      throw Exception('Upload confirmation failed');
    }
    return DateTime.parse(
      (jsonDecode(complete.body) as Map<String, dynamic>)['updatedAt']
          as String,
    );
  }

  Future<void> keepLocalNameOnCloud(VaultFile file) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to resolve this conflict.');
    final remoteFiles = await listCloudFiles();
    Map<String, dynamic>? remote;
    for (final item in remoteFiles) {
      if (item['id'] == file.id) {
        remote = item;
        break;
      }
    }
    if (remote == null) throw StateError('The cloud copy was removed.');
    final uri = await _uri('files/${file.id}');
    final response = await _client.patch(
      uri,
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'name': file.name,
        'expectedUpdatedAt': remote['updatedAt'],
      }),
    );
    if (response.statusCode == 409) throw const SyncConflict();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('The cloud name could not be updated.');
    }
    await vault.markSynced(
      file.id,
      DateTime.parse(
        (jsonDecode(response.body) as Map<String, dynamic>)['updatedAt']
            as String,
      ),
    );
  }
}

class SyncConflict implements Exception {
  const SyncConflict();
}

class UploadCancelled implements Exception {
  const UploadCancelled();
}
