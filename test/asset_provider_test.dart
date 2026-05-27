import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/providers/asset_provider.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_asset_test_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(AssetTagAdapter());
    Hive.registerAdapter(AssetAdapter());
  });

  setUp(() async {
    await Hive.openBox<Asset>('assets');
    await Hive.box<Asset>('assets').clear();
  });

  tearDown(() async {
    await Hive.box<Asset>('assets').close();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('loads previously stored assets when the notifier is created', () async {
    const asset = Asset(
      id: 'stored-cash',
      type: AssetType.cash,
      amount: 350,
      unit: 'EUR',
      currency: 'EUR',
      tag: AssetTag.salary,
    );

    await Hive.box<Asset>('assets').put(asset.id, asset);
    await Hive.box<Asset>('assets').close();
    await Hive.openBox<Asset>('assets');

    final notifier = AssetNotifier();
    addTearDown(notifier.dispose);

    expect(notifier.state, hasLength(1));
    expect(notifier.state.single.id, asset.id);
    expect(notifier.state.single.amount, asset.amount);
    expect(notifier.state.single.currency, asset.currency);
    expect(notifier.state.single.tag, AssetTag.salary);
  });

  test('adds and deletes assets in storage and notifier state', () async {
    const asset = Asset(
      id: 'gold-holding',
      type: AssetType.gold,
      amount: 25,
      unit: 'g',
    );
    final notifier = AssetNotifier();
    addTearDown(notifier.dispose);

    await notifier.addAsset(asset);

    expect(notifier.state.single.id, asset.id);
    expect(Hive.box<Asset>('assets').get(asset.id)?.amount, asset.amount);

    await notifier.removeAsset(asset.id);

    expect(notifier.state, isEmpty);
    expect(Hive.box<Asset>('assets').get(asset.id), isNull);
  });

  test('updates an asset in storage and notifier state', () async {
    const original = Asset(
      id: 'bank-savings',
      type: AssetType.bankSavings,
      amount: 500,
      unit: 'USD',
    );
    const updated = Asset(
      id: 'bank-savings',
      type: AssetType.bankSavings,
      amount: 750,
      unit: 'USD',
      note: 'Monthly deposit',
    );
    final notifier = AssetNotifier();
    addTearDown(notifier.dispose);

    await notifier.addAsset(original);
    await notifier.updateAsset(updated);

    expect(notifier.state.single.amount, updated.amount);
    expect(notifier.state.single.note, updated.note);
    expect(Hive.box<Asset>('assets').get(updated.id)?.amount, updated.amount);
  });
}
