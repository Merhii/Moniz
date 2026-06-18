import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class AppLockStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureAppLockStorage implements AppLockStorage {
  const SecureAppLockStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(migrateWithBackup: true),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AppLockService {
  AppLockService({required AppLockStorage storage}) : _storage = storage;

  static const credentialsKey = 'appLockCredentialsV1';
  static const biometricsEnabledKey = 'appLockBiometricsEnabled';
  static final _pinPattern = RegExp(r'^\d{4}$');

  final AppLockStorage _storage;

  Future<bool> isEnabled() async {
    final encoded = await _storage.read(credentialsKey);
    if (encoded == null) return false;
    _decodeCredentials(encoded);
    return true;
  }

  Future<void> savePin(String pin) async {
    _validatePin(pin);
    final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final credentials = <String, Object>{
      'version': 1,
      'salt': base64Encode(salt),
      'hash': _hashPin(pin, salt),
    };
    await _storage.write(credentialsKey, jsonEncode(credentials));
  }

  Future<bool> verifyPin(String pin) async {
    if (!_pinPattern.hasMatch(pin)) return false;
    final encoded = await _storage.read(credentialsKey);
    if (encoded == null) return false;
    final credentials = _decodeCredentials(encoded);
    final candidate = base64Decode(_hashPin(pin, credentials.salt));
    final expected = base64Decode(credentials.hash);
    return _constantTimeEquals(candidate, expected);
  }

  Future<void> removePin() async {
    await _storage.delete(biometricsEnabledKey);
    await _storage.delete(credentialsKey);
  }

  Future<bool> areBiometricsEnabled() async {
    return await _storage.read(biometricsEnabledKey) == 'true';
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    if (enabled) {
      await _storage.write(biometricsEnabledKey, 'true');
    } else {
      await _storage.delete(biometricsEnabledKey);
    }
  }

  _PinCredentials _decodeCredentials(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, dynamic> || value['version'] != 1) {
        throw const FormatException('Unsupported app-lock credentials.');
      }
      final salt = base64Decode(value['salt'] as String);
      final hash = value['hash'] as String;
      if (salt.length != 32 || base64Decode(hash).length != 32) {
        throw const FormatException('Invalid app-lock credentials.');
      }
      return _PinCredentials(salt: salt, hash: hash);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid app-lock credentials.');
    }
  }

  String _hashPin(String pin, List<int> salt) {
    final digest = Hmac(sha256, salt).convert(utf8.encode(pin));
    return base64Encode(digest.bytes);
  }

  bool _constantTimeEquals(List<int> candidate, List<int> expected) {
    if (candidate.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < candidate.length; index++) {
      difference |= candidate[index] ^ expected[index];
    }
    return difference == 0;
  }

  void _validatePin(String pin) {
    if (!_pinPattern.hasMatch(pin)) {
      throw const FormatException('PIN must contain exactly four digits.');
    }
  }
}

class _PinCredentials {
  const _PinCredentials({required this.salt, required this.hash});

  final List<int> salt;
  final String hash;
}
