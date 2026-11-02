# Keepsake

Keepsake is an offline-first, end-to-end encrypted file vault. This repository contains a Flutter client and a NestJS API. The API stores encrypted file bytes in private S3-compatible storage and keeps only file metadata in PostgreSQL.

## Architecture

- `mobile/`: Flutter / Dart app. Files are encrypted on-device with per-file AES-256-GCM keys. Device wrapping keys are held by iOS Keychain / Android Keystore through `flutter_secure_storage`; `local_auth` gates opening the vault.
- `server/`: NestJS API, PostgreSQL metadata via Prisma, JWT bearer authentication, and short-lived scoped S3 upload/download URLs.
- The server never receives file encryption keys or plaintext file contents. It can see account identifiers, file IDs, encrypted sizes, timestamps, and file names. Folder labels currently stay local.

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

The initial client implements encrypted local import, local search and folders, rename/delete, delete tombstones, image/PDF/text preview, account sign-in, streaming encrypted upload, cloud file browsing/download, and a client-encrypted recovery code for moving the vault key to another device. Folder changes stay local; password/session recovery and background sync are not implemented. Review `SECURITY.md` before handling real user data.

## Security status

This is an implementation starter, not an audited security product. See `SECURITY.md` for threat boundaries, key recovery assumptions, and unfinished production controls.
