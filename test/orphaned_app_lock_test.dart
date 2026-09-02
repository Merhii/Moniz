import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/main.dart';
import 'package:moniz/services/app_lock_service.dart';

void main() {
  test('a PIN left by a previous install is dropped on a fresh one', () async {
    final storage = _InMemoryAppLockStorage();
    final service = AppLockService(storage: storage, iterations: 1000);
    await service.savePin('2468');
    await service.setBiometricsEnabled(true);

    await discardOrphanedAppLock(isFreshInstall: true, storage: storage);

    // Otherwise the user meets a lock screen guarding an empty database, with
    // no way past it.
    expect(await service.isEnabled(), isFalse);
    expect(await service.areBiometricsEnabled(), isFalse);
  });

  test('a PIN set during normal use survives a relaunch', () async {
    final storage = _InMemoryAppLockStorage();
    final service = AppLockService(storage: storage, iterations: 1000);
    await service.savePin('2468');

    // Second and later launches: the box files already exist.
    await discardOrphanedAppLock(isFreshInstall: false, storage: storage);

    expect(await service.isEnabled(), isTrue);
    expect(await service.verifyPin('2468'), isTrue);
  });

  test('does nothing when no credential was left behind', () async {
    final storage = _InMemoryAppLockStorage();

    await discardOrphanedAppLock(isFreshInstall: true, storage: storage);

    expect(storage.values, isEmpty);
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
