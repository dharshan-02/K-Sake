import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/vault_file.dart';
import 'local_vault.dart';

class ApiClient {
  ApiClient(this.vault);
  final LocalVault vault;
  static const _storage = FlutterSecureStorage();
  static const _ownerKey = 'vault_account_owner_v1';
  static const _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000/v1');
  final _client = http.Client();
  final _aead = AesGcm.with256bits();

  Future<void> authenticate(String email, String password, {required bool createAccount}) async {
    final uri = Uri.parse('$_baseUrl/auth/${createAccount ? 'register' : 'login'}');
    final response = await _client.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email, 'password': password}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Could not sign in. Check your details and try again.');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['accessToken'] as String;
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('The server returned an invalid access token.');
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    final subject = claims['sub'] as String;
    final linkedAccount = await _storage.read(key: _ownerKey);
    if (linkedAccount != null && linkedAccount != subject) {
      throw StateError('This local vault is linked to another account. Account switching needs a reviewed vault migration flow.');
    }
    await _storage.write(key: _ownerKey, value: subject);
    await _storage.write(key: 'account_access_token', value: token);
  }

  Future<bool> get hasSession async => await _storage.read(key: 'account_access_token') != null;
  Future<void> signOut() => _storage.delete(key: 'account_access_token');

  Future<String> createRecoveryCode() async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in before setting up recovery.');
    final codeBytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final code = _encode(codeBytes);
    final masterBytes = base64Url.decode(base64Url.normalize(await vault.masterKeyForRecovery()));
    final box = await _aead.encrypt(masterBytes, secretKey: SecretKey(codeBytes));
    await _storage.write(key: 'pending_recovery_code_v1', value: code);
    try {
      final response = await _client.put(Uri.parse('$_baseUrl/keys/recovery'), headers: {
        'authorization': 'Bearer $token', 'content-type': 'application/json',
      }, body: jsonEncode({'nonce': _encode(box.nonce), 'ciphertext': _encode([...box.cipherText, ...box.mac.bytes])}));
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Recovery setup could not be saved.');
      return code;
    } catch (_) {
      await _storage.delete(key: 'pending_recovery_code_v1');
      rethrow;
    }
  }

  Future<String?> pendingRecoveryCode() => _storage.read(key: 'pending_recovery_code_v1');
  Future<void> acknowledgeRecoveryCode() => _storage.delete(key: 'pending_recovery_code_v1');

  Future<void> restoreWithRecoveryCode(String code) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in before restoring your vault.');
    final codeBytes = base64Url.decode(base64Url.normalize(code.trim()));
    if (codeBytes.length != 32) throw const FormatException('Enter the complete 43-character recovery code.');
    final response = await _client.get(Uri.parse('$_baseUrl/keys/recovery'), headers: {'authorization': 'Bearer $token'});
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No recovery code is set for this account.');
    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    final combined = base64Url.decode(base64Url.normalize(envelope['ciphertext'] as String));
    if (combined.length != 48) throw const FormatException('Recovery data is invalid.');
    final box = SecretBox(combined.sublist(0, 32), nonce: base64Url.decode(base64Url.normalize(envelope['nonce'] as String)), mac: Mac(combined.sublist(32)));
    final master = await _aead.decrypt(box, secretKey: SecretKey(codeBytes));
    await vault.restoreMasterKey(_encode(master));
  }

  String _encode(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

  Future<int> syncQueued() async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to sync your vault.');
    var completed = 0;
    for (final id in vault.pendingDeletes()) {
      try {
        final response = await _client.delete(Uri.parse('$_baseUrl/files/$id'), headers: {'authorization': 'Bearer $token'});
        if ((response.statusCode >= 200 && response.statusCode < 300) || response.statusCode == 404) await vault.completeDelete(id);
      } catch (_) { /* Retry the tombstone at the next sync. */ }
    }
    for (final file in await vault.listFiles()) {
      if (file.syncState == 'synced' || file.syncState == 'conflict') continue;
      await vault.setSyncState(file.id, 'uploading');
      try {
        if (file.syncState == 'rename_pending') {
          if (file.remoteUpdatedAt != null) {
            final renamed = await _client.patch(Uri.parse('$_baseUrl/files/${file.id}'), headers: {
              'authorization': 'Bearer $token', 'content-type': 'application/json',
            }, body: jsonEncode({'name': file.name, 'expectedUpdatedAt': file.remoteUpdatedAt!.toUtc().toIso8601String()}));
            if (renamed.statusCode == 409) throw const SyncConflict();
            if (renamed.statusCode < 200 || renamed.statusCode >= 300) throw Exception('Rename sync failed');
            final updatedAt = DateTime.parse((jsonDecode(renamed.body) as Map<String, dynamic>)['updatedAt'] as String);
            await vault.markSynced(file.id, updatedAt);
            completed++;
            continue;
          }
          await vault.setSyncState(file.id, 'queued');
        }
        final updatedAt = await _upload(token, file);
        await vault.markSynced(file.id, updatedAt);
        completed++;
      } on SyncConflict {
        await vault.setSyncState(file.id, 'conflict');
      } catch (_) {
        await vault.setSyncState(file.id, 'failed');
      }
    }
    return completed;
  }

  Future<List<Map<String, dynamic>>> listCloudFiles() async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to view your cloud files.');
    final response = await _client.get(Uri.parse('$_baseUrl/files'), headers: {'authorization': 'Bearer $token'});
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Cloud files could not be loaded. Sign in again and retry.');
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> downloadToVault(Map<String, dynamic> file) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to download files.');
    final id = file['id'] as String;
    final metadata = await _client.get(Uri.parse('$_baseUrl/files/$id/download'), headers: {'authorization': 'Bearer $token'});
    if (metadata.statusCode < 200 || metadata.statusCode >= 300) throw Exception('A download link could not be created.');
    final url = (jsonDecode(metadata.body) as Map<String, dynamic>)['downloadUrl'] as String;
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Encrypted file download failed.');
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

  Future<DateTime> _upload(String token, VaultFile file) async {
    final headers = {'authorization': 'Bearer $token', 'content-type': 'application/json'};
    final base = Uri.parse('$_baseUrl/files/');
    final begin = await _client.post(base.resolve('upload'), headers: headers, body: jsonEncode({
      'id': file.id, 'name': file.name, 'mimeType': 'application/octet-stream', 'size': file.size,
    }));
    if (begin.statusCode < 200 || begin.statusCode >= 300) throw Exception('Upload could not be started');
    final payload = jsonDecode(begin.body) as Map<String, dynamic>;
    if (payload['alreadyUploaded'] == true) return DateTime.parse(payload['updatedAt'] as String);
    final request = http.StreamedRequest('PUT', Uri.parse(payload['uploadUrl'] as String));
    request.headers['content-type'] = 'application/octet-stream';
    final local = File(file.localPath);
    request.contentLength = await local.length();
    final sendFuture = _client.send(request);
    await request.sink.addStream(local.openRead());
    await request.sink.close();
    final response = await sendFuture;
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Encrypted file upload failed');
    final complete = await _client.post(base.resolve('${file.id}/complete'), headers: headers);
    if (complete.statusCode < 200 || complete.statusCode >= 300) throw Exception('Upload confirmation failed');
    return DateTime.parse((jsonDecode(complete.body) as Map<String, dynamic>)['updatedAt'] as String);
  }

  Future<void> keepLocalNameOnCloud(VaultFile file) async {
    final token = await _storage.read(key: 'account_access_token');
    if (token == null) throw StateError('Sign in to resolve this conflict.');
    final remoteFiles = await listCloudFiles();
    Map<String, dynamic>? remote;
    for (final item in remoteFiles) { if (item['id'] == file.id) { remote = item; break; } }
    if (remote == null) throw StateError('The cloud copy was removed.');
    final response = await _client.patch(Uri.parse('$_baseUrl/files/${file.id}'), headers: {
      'authorization': 'Bearer $token', 'content-type': 'application/json',
    }, body: jsonEncode({'name': file.name, 'expectedUpdatedAt': remote['updatedAt']}));
    if (response.statusCode == 409) throw const SyncConflict();
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('The cloud name could not be updated.');
    await vault.markSynced(file.id, DateTime.parse((jsonDecode(response.body) as Map<String, dynamic>)['updatedAt'] as String));
  }
}

class SyncConflict implements Exception {
  const SyncConflict();
}
