import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/services/app_lock_service.dart';

void main() {
  test('stores only a salted verifier and validates the PIN', () async {
    final storage = _InMemoryAppLockStorage();
    final service = AppLockService(storage: storage);

    await service.savePin('4826');

    expect(await service.isEnabled(), isTrue);
    expect(await service.verifyPin('4826'), isTrue);
    expect(await service.verifyPin('4825'), isFalse);
    expect(storage.values.values.join(), isNot(contains('4826')));
  });

  test('rejects PINs that are not exactly four digits', () async {
    final service = AppLockService(storage: _InMemoryAppLockStorage());

    await expectLater(service.savePin('123'), throwsFormatException);
    await expectLater(service.savePin('12a4'), throwsFormatException);
  });

  test('removing the PIN disables lock and biometrics', () async {
    final service = AppLockService(storage: _InMemoryAppLockStorage());
    await service.savePin('1234');
    await service.setBiometricsEnabled(true);

    await service.removePin();

    expect(await service.isEnabled(), isFalse);
    expect(await service.areBiometricsEnabled(), isFalse);
    expect(await service.verifyPin('1234'), isFalse);
  });

  test('derives PBKDF2-HMAC-SHA256 matching the published vectors', () {
    // P = "password", S = "salt", dkLen = 32.
    expect(
      _hex(
        AppLockService.pbkdf2(
          password: utf8.encode('password'),
          salt: utf8.encode('salt'),
          iterations: 1,
          keyLength: 32,
        ),
      ),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      _hex(
        AppLockService.pbkdf2(
          password: utf8.encode('password'),
          salt: utf8.encode('salt'),
          iterations: 2,
          keyLength: 32,
        ),
      ),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  test('stores a slow PBKDF2 verifier rather than a single hash', () async {
    final storage = _InMemoryAppLockStorage();
    await AppLockService(storage: storage, iterations: 1000).savePin('4826');

    final stored =
        jsonDecode(storage.values[AppLockService.credentialsKey]!)
            as Map<String, dynamic>;
    expect(stored['version'], 2);
    expect(stored['iterations'], 1000);
  });

  test(
    'locks out after repeated wrong PINs and recovers when it expires',
    () async {
      var now = DateTime(2026, 8, 30, 12);
      final storage = _InMemoryAppLockStorage();
      final service = AppLockService(
        storage: storage,
        iterations: 1000,
        now: () => now,
      );
      await service.savePin('4826');

      for (
        var attempt = 0;
        attempt < AppLockService.attemptsBeforeLockout;
        attempt++
      ) {
        expect(await service.verifyPin('0000'), isFalse);
      }

      final remaining = await service.lockoutRemaining();
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, greaterThan(0));

      // The correct PIN is refused while the cooldown is running.
      expect(await service.verifyPin('4826'), isFalse);

      now = now.add(const Duration(minutes: 1));
      expect(await service.lockoutRemaining(), isNull);
      expect(await service.verifyPin('4826'), isTrue);
      expect(await service.lockoutRemaining(), isNull);
    },
  );

  test('lengthens the cooldown as failures pile up', () async {
    var now = DateTime(2026, 8, 30, 12);
    final service = AppLockService(
      storage: _InMemoryAppLockStorage(),
      iterations: 1000,
      now: () => now,
    );
    await service.savePin('4826');

    for (
      var attempt = 0;
      attempt < AppLockService.attemptsBeforeLockout;
      attempt++
    ) {
      await service.verifyPin('0000');
    }
    final first = (await service.lockoutRemaining())!;

    now = now.add(const Duration(minutes: 1));
    await service.verifyPin('0000');
    final second = (await service.lockoutRemaining())!;

    expect(second, greaterThan(first));
  });

  test('accepts a legacy verifier and upgrades it on success', () async {
    final storage = _InMemoryAppLockStorage();
    final salt = List<int>.generate(32, (index) => index);
    await storage.write(
      AppLockService.credentialsKey,
      jsonEncode({
        'version': 1,
        'salt': base64Encode(salt),
        'hash': base64Encode(
          Hmac(sha256, salt).convert(utf8.encode('4826')).bytes,
        ),
      }),
    );

    final service = AppLockService(storage: storage, iterations: 1000);
    expect(await service.isEnabled(), isTrue);
    expect(await service.verifyPin('0000'), isFalse);
    expect(await service.verifyPin('4826'), isTrue);

    final upgraded =
        jsonDecode(storage.values[AppLockService.credentialsKey]!)
            as Map<String, dynamic>;
    expect(upgraded['version'], 2);
    expect(upgraded['iterations'], 1000);
    expect(await service.verifyPin('4826'), isTrue);
  });
}

String _hex(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class _InMemoryAppLockStorage implements AppLockStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
