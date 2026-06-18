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
