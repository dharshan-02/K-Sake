import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vault_file.dart';
import 'local_vault.dart';

class FirebaseSyncService {
  FirebaseSyncService(this.vault);
  final LocalVault vault;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const int _chunkSize = 650 * 1024; // ~650 KB to stay well within Firestore 1 MB document limit

  User? get currentUser => _auth.currentUser;
  bool get isAuthenticated => _auth.currentUser != null;
  String? get userEmail => _auth.currentUser?.email;

  Future<UserCredential> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await vault.setMasterKeyFromCredentials(email.trim(), password);
    return credential;
  }

  Future<UserCredential> signUp(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await vault.setMasterKeyFromCredentials(email.trim(), password);
    return credential;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _filesCollection(String uid) =>
      _userDoc(uid).collection('files');

  /// Upload an encrypted local vault file to Cloud Firestore
  Future<void> uploadFile(VaultFile file) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in with your email to upload files.');

    await vault.setSyncState(file.id, 'uploading');
    try {
      final localFile = File(file.localPath);
      if (!await localFile.exists()) {
        throw StateError('Local file not found on disk.');
      }

      final bytes = await localFile.readAsBytes();
      final totalLength = bytes.length;
      final fileRef = _filesCollection(user.uid).doc(file.id);

      final now = DateTime.now().toUtc();

      if (totalLength <= _chunkSize) {
        // Single document upload
        await fileRef.set({
          'id': file.id,
          'name': file.name,
          'mimeType': file.mimeType,
          'size': file.size,
          'createdAt': file.createdAt.toUtc().toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'chunkCount': 1,
          'ciphertext': base64Encode(bytes),
        });
      } else {
        // Chunked upload for larger files
        final chunkCount = (totalLength / _chunkSize).ceil();
        final chunksRef = fileRef.collection('chunks');

        await fileRef.set({
          'id': file.id,
          'name': file.name,
          'mimeType': file.mimeType,
          'size': file.size,
          'createdAt': file.createdAt.toUtc().toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'chunkCount': chunkCount,
          'isChunked': true,
        });

        for (var i = 0; i < chunkCount; i++) {
          final start = i * _chunkSize;
          final end = (start + _chunkSize < totalLength) ? start + _chunkSize : totalLength;
          final chunkBytes = bytes.sublist(start, end);
          await chunksRef.doc(i.toString().padLeft(4, '0')).set({
            'index': i,
            'data': base64Encode(chunkBytes),
          });
        }
      }

      await vault.markSynced(file.id, now);
    } catch (e) {
      await vault.setSyncState(file.id, 'failed');
      debugPrint('Firestore upload error: $e');
      rethrow;
    }
  }

  /// List all files backed up in the user's Firestore cloud account
  Future<List<Map<String, dynamic>>> listCloudFiles() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to view your cloud files.');

    final snapshot = await _filesCollection(user.uid).orderBy('createdAt', descending: true).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  /// Download an encrypted file from Cloud Firestore and decrypt it to the local vault
  Future<void> downloadToVault(Map<String, dynamic> fileData) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to download files.');

    final id = fileData['id'] as String;
    final fileRef = _filesCollection(user.uid).doc(id);

    final Uint8List encryptedBytes;
    if (fileData['isChunked'] == true) {
      final chunksSnap = await fileRef.collection('chunks').orderBy('index').get();
      final byteList = <int>[];
      for (final doc in chunksSnap.docs) {
        final b64 = doc.data()['data'] as String;
        byteList.addAll(base64Decode(b64));
      }
      encryptedBytes = Uint8List.fromList(byteList);
    } else {
      final b64 = fileData['ciphertext'] as String;
      encryptedBytes = base64Decode(b64);
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/firebase-download-$id.tmp');
    await tempFile.writeAsBytes(encryptedBytes);

    try {
      await vault.addDownloadedCiphertext(
        id: id,
        name: fileData['name'] as String,
        mimeType: fileData['mimeType'] as String,
        size: (fileData['size'] as num).toInt(),
        createdAt: DateTime.parse(fileData['createdAt'] as String),
        remoteUpdatedAt: DateTime.parse(fileData['updatedAt'] as String),
        sourcePath: tempFile.path,
      );
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Bi-directional sync: uploads queued local files & downloads missing cloud files
  Future<SyncResult> syncAll({bool downloadMissing = true}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to sync your vault.');

    var uploaded = 0;
    var downloaded = 0;

    // 1. Upload un-synced local files
    final localFiles = await vault.listFiles();
    for (final file in localFiles) {
      if (file.syncState != 'synced') {
        try {
          await uploadFile(file);
          uploaded++;
        } catch (_) {}
      }
    }

    // 2. Download missing cloud files from other phones
    final cloudFiles = await listCloudFiles();
    if (downloadMissing) {
      for (final remote in cloudFiles) {
        final id = remote['id'] as String;
        final exists = await vault.findFile(id);
        if (exists == null) {
          try {
            await downloadToVault(remote);
            downloaded++;
          } catch (_) {}
        }
      }
    }

    return SyncResult(
      uploaded: uploaded,
      downloaded: downloaded,
      totalCloud: cloudFiles.length,
    );
  }
}

class SyncResult {
  const SyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.totalCloud,
  });
  final int uploaded;
  final int downloaded;
  final int totalCloud;
}
