# Mobile setup

The Flutter app and native Android/iOS runners are in `mobile/`. The checked-in project targets Flutter 3.47.5 / Dart 3.13.4. Android Studio is optional for CLI builds, but recommended for editing and emulator management.

## Android

1. Install Flutter stable and Android Studio from their official sites.
2. In Android Studio's Setup Wizard or SDK Manager, install the Android SDK Platform and Build Tools required by the app. An emulator system image is only needed to run a virtual device; it is not needed to compile an APK. The 2 GB Google Play x86_64 image can be skipped when its download is unreliable.
3. From `mobile/`, run `flutter pub get` and `flutter doctor -v`.
4. Build a debug APK with `flutter build apk --debug`. It is written to `build/app/outputs/flutter-apk/app-debug.apk`.
5. To install on a connected Android device, enable developer options and USB debugging, connect the device, then run `flutter install`.

Android requests `INTERNET` for the API and `USE_BIOMETRIC` for OS local authentication. The app never receives biometric data. Release signing is not configured; the debug signing key must not be used for distribution.

## iOS

The iOS runner is generated, but building it requires macOS with Xcode. Add `NSFaceIDUsageDescription` to `ios/Runner/Info.plist` and follow the `local_auth` setup for the current iOS plugin version before running on a device.

## API and object storage

Cloud account creation needs the NestJS API and PostgreSQL to be running. The Android emulator can reach a host API at `http://10.0.2.2:3000/v1`; a physical Android phone cannot use `10.0.2.2`. Put the phone and development computer on the same Wi-Fi, then set the Server address in the sign-up screen to `http://<computer-wi-fi-ip>:3000/v1` (for example, `http://192.168.1.20:3000/v1`). Allow inbound connections to ports 3000 and, for file transfers, 9000 in the computer firewall. The debug Android build permits HTTP for local development only; use HTTPS for deployed servers.

For local development, copy `server/.env.example` to `server/.env`, set a random `JWT_SECRET` of at least 32 bytes, start Docker Desktop, then run `docker compose up -d --build`. The compose file supplies development-only PostgreSQL and MinIO credentials; never reuse them for production. Registration does not need a separate third-party API key. Cloud file uploads also need the private S3-compatible MinIO/S3 store. For a physical phone, set `S3_PUBLIC_ENDPOINT=http://<computer-wi-fi-ip>:9000` in `server/.env` so the signed upload/download link reaches the host from the phone. Use HTTPS and real database/object-storage credentials for production.

The current launch lock calls the OS local authentication API before initializing the vault. It does not yet configure a hardware-backed biometric access-control list on the database key; do not treat the launch lock as an audited key-management implementation. See `SECURITY.md` for recovery assumptions, metadata visibility, and limitations.
