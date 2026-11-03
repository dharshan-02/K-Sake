# Keepsake

Keepsake is an offline-first, end-to-end encrypted file vault. This repository contains a Flutter client and a NestJS API. The API stores encrypted file bytes in private S3-compatible storage and keeps only file metadata in PostgreSQL.

## Architecture

- `mobile/`: Flutter / Dart app. Files are encrypted on-device with per-file AES-256-GCM keys. Device wrapping keys are held by iOS Keychain / Android Keystore through `flutter_secure_storage`; `local_auth` gates opening the vault.
- `server/`: NestJS API, PostgreSQL metadata via Prisma, JWT bearer authentication, and short-lived scoped S3 upload/download URLs.
- The server never receives file encryption keys or plaintext file contents. It can see account identifiers, file IDs, encrypted sizes, timestamps, file names, and active device labels/last-active times. Folder labels stay local and are not synced.

## Start the API

Requirements: Node.js 22+, PostgreSQL 16+, and a private S3-compatible bucket (MinIO works locally). Copy `server/.env.example` to `server/.env`, set secrets, and configure the database and S3 endpoint. To run PostgreSQL and MinIO with Docker, start with `docker compose up -d postgres minio minio-init`; for the API container, use `docker compose up --build api`. For local Node development, point `.env` at `localhost` and run:

```sh
cd server
npm install
npm run db:generate
npm run db:migrate
npm run start:dev
```

The API defaults to `http://localhost:3000`. Configure the mobile API URL for your simulator/device; a physical device needs a reachable host address and HTTPS outside local development.

## Start the mobile app 

Install Flutter 3.47.5 stable and Android Studio with the Android SDK. Native Android and iOS runner folders are included. From `mobile/`:

```sh
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=https://your-api.example
```

Build an Android debug APK with `flutter build apk --debug`; the APK is written to `mobile/build/app/outputs/flutter-apk/app-debug.apk`. A virtual device is optional for building. Release signing is not configured.

The client implements encrypted local import, searchable folders, file type/date/sync filters, rename, a recoverable Recycle Bin, image/PDF/video preview, gallery upload and cloud download, account sign-in, streaming encrypted upload, cloud file browsing, and a client-encrypted recovery code for moving the vault key to another device. Search and filters apply to this device's local file list; cloud search is not implemented. Empty folders can be created locally. Folder labels are not synced. Settings include a working background auto-lock timer and a signed-in device list with server-side session revocation. Revocation blocks that device's future API requests but cannot erase files it already downloaded.

The notification bell opens a local activity inbox and updates while app actions happen. It is not a remote push-notification service; background or cross-device push delivery still needs a configured push provider. The Hidden Safe is a PIN-gated local view that never uploads its files. It shares the device vault encryption key with regular files, so it is not a separate cryptographic vault. Files moved there from cloud storage queue cloud deletion for the next regular-vault sync. Review `SECURITY.md` before handling real user data.

For a local UI walkthrough, a debug build includes a device-local demo account. Use `demo@keepsake.local` with password `KeepsakeDemo!2026`, or choose **Open demo vault** on the sign-in screen. This demo does not contact the API or sync data and is excluded from release builds; do not use these credentials for real data. Cloud sign-in and registration need the API and PostgreSQL/S3 services running.

Registration offers a **Cloud account** or **Device only** vault. Device-only files remain on this device. Cloud files are encrypted on-device before upload. Per-file states show whether a file is local, queued, uploading, synced, or needs attention. Interrupted or cancelled uploads keep the encrypted local copy and return to the queue; retry starts the upload again when connected. If the app closes mid-upload, the next unlock also returns stale `uploading` items to the retryable queue.

The API records one active cloud session per app installation. Apply the new `DeviceSession` Prisma migration before deploying this version. Existing users must sign in again once after deployment so their session gets registered; signing out or revoking a device prevents its current token from authorizing further API requests. The device list shows a generic platform label plus a short local identifier, not a hardware serial number.

## Security status

This is an implementation starter, not an audited security product. See `SECURITY.md` for threat boundaries, key recovery assumptions, and unfinished production controls.
