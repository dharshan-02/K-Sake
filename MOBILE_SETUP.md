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

Set `API_BASE_URL` when starting the app. Android emulator can reach a host development API at `http://10.0.2.2:3000/v1`; iOS simulator can use `http://127.0.0.1:3000/v1`. Physical devices need the host's LAN address for local development. For emulator object uploads, set `S3_PUBLIC_ENDPOINT=http://10.0.2.2:9000` in `server/.env`; iOS simulator can use `http://127.0.0.1:9000`. Use HTTPS for any non-local deployment.

The current launch lock calls the OS local authentication API before initializing the vault. It does not yet configure a hardware-backed biometric access-control list on the database key; do not treat the launch lock as an audited key-management implementation. See `SECURITY.md` for recovery assumptions, metadata visibility, and limitations.
