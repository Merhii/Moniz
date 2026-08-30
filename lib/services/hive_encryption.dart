import 'dart:convert';
import 'dart:math';

import 'package:hive/hive.dart';

import 'app_lock_service.dart' show AppLockStorage, SecureAppLockStorage;

/// Opens Hive boxes encrypted at rest, converting any box left behind by an
/// earlier build that wrote plaintext.
///
/// The key lives in the platform keychain/keystore, reusing [AppLockStorage]
/// as a general secure key-value store. Losing that entry means losing the
/// data, which is the same trade the platform already makes for the app-lock
/// PIN.
class HiveEncryption {
  HiveEncryption({AppLockStorage? storage})
    : _storage = storage ?? const SecureAppLockStorage();

  static const keyStorageKey = 'hiveEncryptionKeyV1';
  static const _encryptedMarkerPrefix = 'hiveBoxEncryptedV1:';
  static const _stagingSuffix = '__encrypting';
  static const _stagingCompleteKey = '__staging_complete';

  final AppLockStorage _storage;

  /// Returns the cipher every box should be opened with, after making sure
  /// [boxNames] are all stored encrypted.
  Future<HiveAesCipher> bootstrap(List<String> boxNames) async {
    final cipher = HiveAesCipher(await _key());
    for (final name in boxNames) {
      await _migrateBox(name, cipher);
    }
    return cipher;
  }

  Future<List<int>> _key() async {
    final existing = await _storage.read(keyStorageKey);
    if (existing != null) {
      final key = base64Decode(existing);
      if (key.length == 32) return key;
    }
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    // Persisted before anything is encrypted with it. Generating a second key
    // after a half-finished run would make the already-converted boxes
    // unreadable.
    await _storage.write(keyStorageKey, base64Encode(key));
    return key;
  }

  Future<void> _migrateBox(String name, HiveAesCipher cipher) async {
    final marker = '$_encryptedMarkerPrefix$name';
    final staging = '$name$_stagingSuffix';

    if (await _storage.read(marker) == 'true') return;

    if (await Hive.boxExists(staging)) {
      final staged = await Hive.openBox<dynamic>(
        staging,
        encryptionCipher: cipher,
      );
      if (staged.get(_stagingCompleteKey) == true) {
        // The plaintext box is already gone; the staged copy is the only
        // complete record left.
        await _publish(staged, name, cipher);
        await _storage.write(marker, 'true');
        return;
      }
      // Interrupted while staging, so it may be partial. The plaintext box is
      // still intact, so throw this away and start over.
      await staged.close();
      await Hive.deleteBoxFromDisk(staging);
    }

    if (!await Hive.boxExists(name)) {
      // Nothing written yet; whatever is created next is encrypted anyway.
      await _storage.write(marker, 'true');
      return;
    }

    final plain = await Hive.openBox<dynamic>(name);
    final entries = Map<dynamic, dynamic>.of(plain.toMap());
    await plain.close();

    final staged = await Hive.openBox<dynamic>(
      staging,
      encryptionCipher: cipher,
    );
    await staged.clear();
    await staged.putAll(entries);
    await staged.put(_stagingCompleteKey, true);
    await staged.flush();

    await Hive.deleteBoxFromDisk(name);
    await _publish(staged, name, cipher);
    await _storage.write(marker, 'true');
  }

  /// Copies a completed staging box onto [name] and removes the staging copy.
  /// Safe to repeat: the target is rebuilt from scratch each time.
  Future<void> _publish(
    Box<dynamic> staged,
    String name,
    HiveAesCipher cipher,
  ) async {
    final entries = Map<dynamic, dynamic>.of(staged.toMap())
      ..remove(_stagingCompleteKey);
    await staged.close();

    await Hive.deleteBoxFromDisk(name);
    final target = await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
    await target.putAll(entries);
    await target.flush();
    await target.close();

    await Hive.deleteBoxFromDisk('$name$_stagingSuffix');
  }
}
