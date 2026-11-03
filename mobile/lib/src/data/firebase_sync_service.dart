import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vault_credential.dart';
import '../models/vault_file.dart';
import '../models/vault_note.dart';
import 'local_vault.dart';

class FirebaseSyncService {
  FirebaseSyncService(this.vault);
  final LocalVault vault;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const int _chunkSize = 650 * 1024; // ~650 KB to stay within Firestore 1 MB document limit

  User? get currentUser => _auth.currentUser;
  bool get isAuthenticated => _auth.currentUser != null;
  String? get userEmail => _auth.currentUser?.email;

  // --- Auth Operations ---

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

  Future<UserCredential> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw StateError('Google Sign-In was cancelled.');
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCred = await _auth.signInWithCredential(credential);
    final email = userCred.user?.email ?? googleUser.email;
    await vault.setMasterKeyFromCredentials(
      email,
      userCred.user?.uid ?? 'google-auth-vault-key',
    );
    return userCred;
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // --- Document References ---

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _filesCollection(String uid) =>
      _userDoc(uid).collection('files');

  CollectionReference<Map<String, dynamic>> _notesCollection(String uid) =>
      _userDoc(uid).collection('notes');

  CollectionReference<Map<String, dynamic>> _credentialsCollection(String uid) =>
      _userDoc(uid).collection('credentials');

  // --- File Storage in Firestore ---

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
        await fileRef.set({
          'id': file.id,
          'name': file.name,
          'mimeType': file.mimeType,
          'size': file.size,
          'folderName': file.folderName,
          'createdAt': file.createdAt.toUtc().toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'chunkCount': 1,
          'ciphertext': base64Encode(bytes),
        });
      } else {
        final chunkCount = (totalLength / _chunkSize).ceil();
        final chunksRef = fileRef.collection('chunks');

        await fileRef.set({
          'id': file.id,
          'name': file.name,
          'mimeType': file.mimeType,
          'size': file.size,
          'folderName': file.folderName,
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

  Future<void> deleteCloudFile(String fileId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final fileRef = _filesCollection(user.uid).doc(fileId);
      final chunksSnap = await fileRef.collection('chunks').get();
      for (final doc in chunksSnap.docs) {
        await doc.reference.delete();
      }
      await fileRef.delete();
    } catch (e) {
      debugPrint('Error deleting cloud file: $e');
    }
  }

  Future<List<Map<String, dynamic>>> listCloudFiles() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to view your cloud files.');

    final snapshot = await _filesCollection(user.uid).orderBy('createdAt', descending: true).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

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

  // --- Notes Storage in Firestore ---

  Future<void> uploadNote(VaultNote note) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _notesCollection(user.uid).doc(note.id).set({
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'colorValue': note.colorValue,
        'isPinned': note.isPinned,
        'isHidden': note.isHidden,
        'createdAt': note.createdAt.toUtc().toIso8601String(),
        'updatedAt': note.updatedAt.toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Firestore uploadNote error: $e');
    }
  }

  Future<void> deleteCloudNote(String noteId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _notesCollection(user.uid).doc(noteId).delete();
    } catch (e) {
      debugPrint('Firestore deleteCloudNote error: $e');
    }
  }

  Future<List<VaultNote>> listCloudNotes() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    try {
      final snapshot = await _notesCollection(user.uid).get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return VaultNote(
          id: data['id'] as String? ?? doc.id,
          title: data['title'] as String? ?? '',
          content: data['content'] as String? ?? '',
          colorValue: (data['colorValue'] as num?)?.toInt() ?? 0xFF1E293B,
          isPinned: data['isPinned'] as bool? ?? false,
          isHidden: data['isHidden'] as bool? ?? false,
          createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(data['updatedAt'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Firestore listCloudNotes error: $e');
      return [];
    }
  }

  // --- Passwords & Credentials Storage in Firestore ---

  Future<void> uploadCredential(VaultCredential cred) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _credentialsCollection(user.uid).doc(cred.id).set({
        'id': cred.id,
        'title': cred.title,
        'username': cred.username,
        'password': cred.password,
        'url': cred.url,
        'notes': cred.notes,
        'category': cred.category,
        'isHidden': cred.isHidden,
        'createdAt': cred.createdAt.toUtc().toIso8601String(),
        'updatedAt': cred.updatedAt.toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Firestore uploadCredential error: $e');
    }
  }

  Future<void> deleteCloudCredential(String credId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _credentialsCollection(user.uid).doc(credId).delete();
    } catch (e) {
      debugPrint('Firestore deleteCloudCredential error: $e');
    }
  }

  Future<List<VaultCredential>> listCloudCredentials() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    try {
      final snapshot = await _credentialsCollection(user.uid).get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return VaultCredential(
          id: data['id'] as String? ?? doc.id,
          title: data['title'] as String? ?? '',
          username: data['username'] as String? ?? '',
          password: data['password'] as String? ?? '',
          url: data['url'] as String?,
          notes: data['notes'] as String?,
          category: data['category'] as String? ?? 'Login',
          isHidden: data['isHidden'] as bool? ?? false,
          createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(data['updatedAt'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Firestore listCloudCredentials error: $e');
      return [];
    }
  }

  // --- Unified Bi-directional Sync ---

  Future<SyncResult> syncAll({bool downloadMissing = true}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in with your email to sync.');

    var uploaded = 0;
    var downloaded = 0;

    // 1. Files Sync
    final localFiles = await vault.listFiles();
    for (final file in localFiles) {
      if (file.syncState != 'synced') {
        try {
          await uploadFile(file);
          uploaded++;
        } catch (_) {}
      }
    }

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

    // 2. Notes Sync
    try {
      final localNotes = await vault.listNotes();
      for (final note in localNotes) {
        await uploadNote(note);
      }
      final remoteNotes = await listCloudNotes();
      for (final rNote in remoteNotes) {
        await vault.saveNote(rNote);
      }
    } catch (e) {
      debugPrint('Notes sync error: $e');
    }

    // 3. Credentials Sync
    try {
      final localCreds = await vault.listCredentials();
      for (final cred in localCreds) {
        await uploadCredential(cred);
      }
      final remoteCreds = await listCloudCredentials();
      for (final rCred in remoteCreds) {
        await vault.saveCredential(rCred);
      }
    } catch (e) {
      debugPrint('Credentials sync error: $e');
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
