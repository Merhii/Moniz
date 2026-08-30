import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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
  AppLockService({
    required AppLockStorage storage,
    int? iterations,
    DateTime Function()? now,
  }) : _storage = storage,
       _iterations = iterations ?? defaultIterations,
       _now = now ?? DateTime.now;

  static const credentialsKey = 'appLockCredentialsV1';
  static const throttleKey = 'appLockThrottleV1';
  static const biometricsEnabledKey = 'appLockBiometricsEnabled';

  /// PBKDF2 rounds for new credentials. A 4-digit PIN is only 10,000
  /// possibilities, so the derivation has to be deliberately slow: at one
  /// round the whole keyspace falls in milliseconds if the stored verifier
  /// ever leaves the device.
  static const defaultIterations = 120000;

  /// Wrong PINs allowed before the next attempt is delayed.
  static const attemptsBeforeLockout = 5;
  static const _baseLockout = Duration(seconds: 30);
  static const _maxLockout = Duration(minutes: 15);

  static const _currentVersion = 2;
  static final _pinPattern = RegExp(r'^\d{4}$');

  final AppLockStorage _storage;
  final int _iterations;
  final DateTime Function() _now;

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
      'version': _currentVersion,
      'salt': base64Encode(salt),
      'iterations': _iterations,
      'hash': base64Encode(
        _pbkdf2(
          password: utf8.encode(pin),
          salt: salt,
          iterations: _iterations,
          keyLength: 32,
        ),
      ),
    };
    await _storage.write(credentialsKey, jsonEncode(credentials));
    await _clearThrottle();
  }

  /// How long until another PIN attempt is accepted, or null if one is
  /// accepted now.
  Future<Duration?> lockoutRemaining() async {
    final lockedUntil = (await _readThrottle()).lockedUntil;
    if (lockedUntil == null) return null;
    final remaining = lockedUntil.difference(_now());
    return remaining > Duration.zero ? remaining : null;
  }

  Future<bool> verifyPin(String pin) async {
    if (await lockoutRemaining() != null) return false;

    final encoded = await _storage.read(credentialsKey);
    if (encoded == null) return false;
    if (!_pinPattern.hasMatch(pin)) {
      await _recordFailure();
      return false;
    }

    final credentials = _decodeCredentials(encoded);
    final candidate = _deriveHash(pin, credentials);
    final matches = _constantTimeEquals(
      candidate,
      base64Decode(credentials.hash),
    );
    if (!matches) {
      await _recordFailure();
      return false;
    }

    await _clearThrottle();
    if (credentials.version < _currentVersion ||
        credentials.iterations < _iterations) {
      // Re-derive with the current cost now that we hold the plaintext PIN.
      await savePin(pin);
    }
    return true;
  }

  Future<void> removePin() async {
    await _storage.delete(biometricsEnabledKey);
    await _storage.delete(credentialsKey);
    await _clearThrottle();
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

  List<int> _deriveHash(String pin, _PinCredentials credentials) {
    if (credentials.version == 1) {
      // Legacy single-pass HMAC. Still verifiable so nobody is locked out by
      // the upgrade; replaced with a PBKDF2 verifier on the next success.
      return Hmac(sha256, credentials.salt).convert(utf8.encode(pin)).bytes;
    }
    return _pbkdf2(
      password: utf8.encode(pin),
      salt: credentials.salt,
      iterations: credentials.iterations,
      keyLength: base64Decode(credentials.hash).length,
    );
  }

  Future<_Throttle> _readThrottle() async {
    final encoded = await _storage.read(throttleKey);
    if (encoded == null) return const _Throttle();
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      final lockedUntilMs = value['lockedUntilMs'] as int?;
      return _Throttle(
        failures: (value['failures'] as num?)?.toInt() ?? 0,
        lockedUntil: lockedUntilMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lockedUntilMs),
      );
    } catch (_) {
      return const _Throttle();
    }
  }

  Future<void> _recordFailure() async {
    final failures = (await _readThrottle()).failures + 1;
    DateTime? lockedUntil;
    if (failures >= attemptsBeforeLockout) {
      final doublings = (failures - attemptsBeforeLockout).clamp(0, 16);
      var penalty = _baseLockout * (1 << doublings);
      if (penalty > _maxLockout) penalty = _maxLockout;
      lockedUntil = _now().add(penalty);
    }
    await _storage.write(
      throttleKey,
      jsonEncode(<String, Object>{
        'failures': failures,
        if (lockedUntil != null)
          'lockedUntilMs': lockedUntil.millisecondsSinceEpoch,
      }),
    );
  }

  Future<void> _clearThrottle() => _storage.delete(throttleKey);

  _PinCredentials _decodeCredentials(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Unsupported app-lock credentials.');
      }
      final version = (value['version'] as num?)?.toInt();
      if (version != 1 && version != _currentVersion) {
        throw const FormatException('Unsupported app-lock credentials.');
      }
      final salt = base64Decode(value['salt'] as String);
      final hash = value['hash'] as String;
      if (salt.length != 32 || base64Decode(hash).length != 32) {
        throw const FormatException('Invalid app-lock credentials.');
      }
      return _PinCredentials(
        version: version!,
        salt: salt,
        hash: hash,
        iterations: (value['iterations'] as num?)?.toInt() ?? 1,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid app-lock credentials.');
    }
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018). `crypto` ships HMAC but no KDF, and this
  /// is a few lines against pulling in another dependency.
  @visibleForTesting
  static List<int> pbkdf2({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    return _pbkdf2(
      password: password,
      salt: salt,
      iterations: iterations,
      keyLength: keyLength,
    );
  }

  static List<int> _pbkdf2({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, password);
    final derived = <int>[];
    for (var block = 1; derived.length < keyLength; block++) {
      var previous = hmac.convert([
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]).bytes;
      final accumulated = List<int>.of(previous);
      for (var round = 1; round < iterations; round++) {
        previous = hmac.convert(previous).bytes;
        for (var index = 0; index < accumulated.length; index++) {
          accumulated[index] ^= previous[index];
        }
      }
      derived.addAll(accumulated);
    }
    return derived.sublist(0, keyLength);
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
  const _PinCredentials({
    required this.version,
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  final int version;
  final List<int> salt;
  final String hash;
  final int iterations;
}

class _Throttle {
  const _Throttle({this.failures = 0, this.lockedUntil});

  final int failures;
  final DateTime? lockedUntil;
}
