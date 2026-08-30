import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/services/app_lock_service.dart';
import 'package:moniz/services/hive_encryption.dart';

void main() {
  late Directory hiveDirectory;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_cipher_test_');
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(AssetTypeAdapter());
      Hive.registerAdapter(AssetTagAdapter());
      Hive.registerAdapter(AssetAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test(
    'converts a plaintext box and leaves nothing readable on disk',
    () async {
      final plain = await Hive.openBox<Asset>('assets');
      await plain.put(
        'gold',
        const Asset(
          id: 'gold',
          type: AssetType.gold,
          amount: 25,
          unit: 'g',
          note: 'inheritance from grandmother',
        ),
      );
      await plain.close();

      expect(
        await _fileContains('assets', hiveDirectory, 'inheritance'),
        isTrue,
      );

      final storage = _InMemoryAppLockStorage();
      final cipher = await HiveEncryption(
        storage: storage,
      ).bootstrap(['assets']);

      final reopened = await Hive.openBox<Asset>(
        'assets',
        encryptionCipher: cipher,
      );
      expect(reopened.get('gold')?.amount, 25);
      expect(reopened.get('gold')?.note, 'inheritance from grandmother');
      await reopened.close();

      expect(
        await _fileContains('assets', hiveDirectory, 'inheritance'),
        isFalse,
      );
      expect(storage.values[HiveEncryption.keyStorageKey], isNotNull);
    },
  );

  test('reuses the stored key across runs', () async {
    final storage = _InMemoryAppLockStorage();
    final first = await HiveEncryption(storage: storage).bootstrap(['assets']);
    final box = await Hive.openBox<Asset>('assets', encryptionCipher: first);
    await box.put(
      'cash',
      const Asset(id: 'cash', type: AssetType.cash, amount: 400, unit: 'USD'),
    );
    await box.close();

    final second = await HiveEncryption(storage: storage).bootstrap(['assets']);
    final reopened = await Hive.openBox<Asset>(
      'assets',
      encryptionCipher: second,
    );
    expect(reopened.get('cash')?.amount, 400);
  });

  test('is a no-op on a second run over an already converted box', () async {
    final storage = _InMemoryAppLockStorage();
    final plain = await Hive.openBox<Asset>('assets');
    await plain.put(
      'silver',
      const Asset(id: 'silver', type: AssetType.silver, amount: 60, unit: 'g'),
    );
    await plain.close();

    await HiveEncryption(storage: storage).bootstrap(['assets']);
    final cipher = await HiveEncryption(storage: storage).bootstrap(['assets']);

    final box = await Hive.openBox<Asset>('assets', encryptionCipher: cipher);
    expect(box.length, 1);
    expect(box.get('silver')?.amount, 60);
  });

  test('recovers when the previous run stopped after staging', () async {
    final storage = _InMemoryAppLockStorage();
    final plain = await Hive.openBox<Asset>('assets');
    await plain.put(
      'gold',
      const Asset(id: 'gold', type: AssetType.gold, amount: 12, unit: 'g'),
    );
    await plain.close();

    // Stand in for a crash between writing the staging copy and rebuilding the
    // real box: staging is complete, the plaintext box is gone.
    final cipher = await HiveEncryption(storage: storage).bootstrap(['assets']);
    final staged = await Hive.openBox<dynamic>(
      'assets__encrypting',
      encryptionCipher: cipher,
    );
    await staged.putAll({
      'gold': const Asset(
        id: 'gold',
        type: AssetType.gold,
        amount: 12,
        unit: 'g',
      ),
      '__staging_complete': true,
    });
    await staged.close();
    await Hive.deleteBoxFromDisk('assets');
    await storage.delete('hiveBoxEncryptedV1:assets');

    final resumed = await HiveEncryption(
      storage: storage,
    ).bootstrap(['assets']);

    final box = await Hive.openBox<Asset>('assets', encryptionCipher: resumed);
    expect(box.get('gold')?.amount, 12);
    expect(box.containsKey('__staging_complete'), isFalse);
    expect(await Hive.boxExists('assets__encrypting'), isFalse);
  });

  test('discards a staging copy that never finished', () async {
    final storage = _InMemoryAppLockStorage();
    final plain = await Hive.openBox<Asset>('assets');
    await plain.put(
      'gold',
      const Asset(id: 'gold', type: AssetType.gold, amount: 30, unit: 'g'),
    );
    await plain.close();

    // A crash mid-staging leaves a partial copy with no completion marker; the
    // plaintext box is still the source of truth.
    final cipher = await HiveEncryption(storage: storage).bootstrap(['assets']);
    await Hive.deleteBoxFromDisk('assets');
    final revertedPlain = await Hive.openBox<Asset>('assets');
    await revertedPlain.put(
      'gold',
      const Asset(id: 'gold', type: AssetType.gold, amount: 30, unit: 'g'),
    );
    await revertedPlain.close();
    final partial = await Hive.openBox<dynamic>(
      'assets__encrypting',
      encryptionCipher: cipher,
    );
    await partial.put('gold', 'garbage');
    await partial.close();
    await storage.delete('hiveBoxEncryptedV1:assets');

    final resumed = await HiveEncryption(
      storage: storage,
    ).bootstrap(['assets']);

    final box = await Hive.openBox<Asset>('assets', encryptionCipher: resumed);
    expect(box.get('gold')?.amount, 30);
    expect(await Hive.boxExists('assets__encrypting'), isFalse);
  });
}

Future<bool> _fileContains(
  String boxName,
  Directory directory,
  String needle,
) async {
  final file = File('${directory.path}/$boxName.hive');
  if (!await file.exists()) return false;
  return String.fromCharCodes(await file.readAsBytes()).contains(needle);
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
