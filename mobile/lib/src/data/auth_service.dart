import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AuthLockType { biometric, pin, pattern, password }

class AuthService {
  static const _storage = FlutterSecureStorage();

  static const _kRegistered = 'auth_is_registered';
  static const _kUserEmail = 'auth_user_email';
  static const _kLockType = 'auth_lock_type';
  static const _kPin = 'auth_pin_code';
  static const _kPattern = 'auth_pattern_code';
  static const _kPassword = 'auth_master_password';
  static const _kHiddenPin = 'auth_hidden_vault_pin';
  static const _kHiddenEnabled = 'auth_hidden_vault_enabled';
  static const _kAutoLockMin = 'auth_auto_lock_minutes';
  static const _kAccountMode = 'account_storage_mode_v1';

  Future<bool> isRegistered() async {
    final val = await _storage.read(key: _kRegistered);
    return val == 'true';
  }

  Future<void> registerUser({
    required String email,
    required String password,
    required AuthLockType lockType,
    bool cloudAccount = true,
    String? pin,
    String? pattern,
  }) async {
    await _storage.write(key: _kRegistered, value: 'true');
    await _storage.write(key: _kUserEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kLockType, value: lockType.name);
    await _storage.write(
      key: _kAccountMode,
      value: cloudAccount ? 'cloud' : 'device',
    );
    if (pin != null) await _storage.write(key: _kPin, value: pin);
    if (pattern != null) await _storage.write(key: _kPattern, value: pattern);
  }

  Future<String?> getUserEmail() => _storage.read(key: _kUserEmail);

  Future<String> getAccountMode() async =>
      (await _storage.read(key: _kAccountMode)) ?? 'device';

  Future<void> saveAccountCredentials({
    required String email,
    required String password,
    required bool cloudAccount,
  }) async {
    await _storage.write(key: _kUserEmail, value: email.trim().toLowerCase());
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(
      key: _kAccountMode,
      value: cloudAccount ? 'cloud' : 'device',
    );
    await _storage.write(key: _kRegistered, value: 'true');
  }

  Future<void> setAccountMode(String mode) =>
      _storage.write(key: _kAccountMode, value: mode);

  Future<AuthLockType> getPreferredLockType() async {
    final typeStr = await _storage.read(key: _kLockType);
    return AuthLockType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => AuthLockType.password,
    );
  }

  Future<void> setPreferredLockType(AuthLockType type) =>
      _storage.write(key: _kLockType, value: type.name);

  Future<String?> getPin() => _storage.read(key: _kPin);
  Future<void> setPin(String pin) => _storage.write(key: _kPin, value: pin);

  Future<String?> getPattern() => _storage.read(key: _kPattern);
  Future<void> setPattern(String pattern) =>
      _storage.write(key: _kPattern, value: pattern);

  Future<String?> getPassword() => _storage.read(key: _kPassword);
  Future<void> setPassword(String password) =>
      _storage.write(key: _kPassword, value: password);

  Future<String> getHiddenVaultPin() async {
    final pin = await _storage.read(key: _kHiddenPin);
    // Older builds silently initialized every new vault with 9999. Treat that
    // legacy default as unset so it cannot act as a known unlock credential.
    return pin == null || pin == '9999' ? '' : pin;
  }

  Future<void> setHiddenVaultPin(String pin) =>
      _storage.write(key: _kHiddenPin, value: pin);

  Future<bool> isHiddenVaultEnabled() async {
    final val = await _storage.read(key: _kHiddenEnabled);
    return val == 'true';
  }

  Future<void> setHiddenVaultEnabled(bool enabled) =>
      _storage.write(key: _kHiddenEnabled, value: enabled ? 'true' : 'false');

  Future<int> getAutoLockMinutes() async {
    final val = await _storage.read(key: _kAutoLockMin);
    return int.tryParse(val ?? '0') ?? 0;
  }

  Future<void> setAutoLockMinutes(int min) =>
      _storage.write(key: _kAutoLockMin, value: min.toString());
}
