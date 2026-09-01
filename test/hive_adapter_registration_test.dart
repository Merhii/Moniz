import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/portfolio_snapshot.dart';
import 'package:moniz/models/zakat_settings.dart';

/// Every other test registers adapters itself, with the concrete type written
/// out. Only the app registers them through main.dart, so only the app hit the
/// bug where a `TypeAdapter<dynamic>` made the first adapter match every value
/// and all writes went to it. These tests go through the app's own path.
void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_adapters_');
    Hive.init(hiveDirectory.path);
    registerMonizAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('an asset written through the app registration reads back', () async {
    final box = await Hive.openBox<Asset>('assets_reg');
    const asset = Asset(
      id: 'cash',
      type: AssetType.cash,
      amount: 500,
      unit: 'USD',
      tag: AssetTag.salary,
    );

    await box.put(asset.id, asset);

    expect(box.get('cash')?.amount, 500);
    expect(box.get('cash')?.type, AssetType.cash);
    expect(box.get('cash')?.tag, AssetTag.salary);
  });

  test('a metal price snapshot round-trips', () async {
    final box = await Hive.openBox<MetalPriceSnapshot>('prices_reg');
    final snapshot = MetalPriceSnapshot(
      goldPerGramUsd: 143.28,
      silverPerGramUsd: 2.14,
      priceTimestamp: DateTime.utc(2026, 9, 1),
      fetchedAt: DateTime.utc(2026, 9, 1),
    );

    await box.put('latest', snapshot);

    expect(box.get('latest')?.goldPerGramUsd, 143.28);
  });

  test('zakat settings and payments round-trip', () async {
    final settings = await Hive.openBox<ZakatSettings>('settings_reg');
    await settings.put(
      'settings',
      ZakatSettings(
        scheduleMode: ZakatScheduleMode.individualDueDates,
        nisabStandard: NisabStandard.gold,
        nextRamadanDueDate: DateTime.utc(2027, 3, 1),
      ),
    );
    expect(
      settings.get('settings')?.scheduleMode,
      ZakatScheduleMode.individualDueDates,
    );
    expect(settings.get('settings')?.nisabStandard, NisabStandard.gold);

    final payments = await Hive.openBox<ZakatPaymentRecord>('payments_reg');
    await payments.put(
      'cash',
      ZakatPaymentRecord(
        referenceId: 'cash',
        paidAt: DateTime.utc(2026, 9, 1),
        amountUsd: 1250,
      ),
    );
    expect(payments.get('cash')?.amountUsd, 1250);
  });

  test('a portfolio snapshot round-trips', () async {
    final box = await Hive.openBox<PortfolioSnapshot>('snapshots_reg');
    final snapshot = PortfolioSnapshot(
      id: 'snap',
      capturedAt: DateTime.utc(2026, 9, 1),
      totalUsd: 4604.51,
      cashUsd: 120,
      bankSavingsUsd: 0,
      goldUsd: 4059,
      silverUsd: 425.51,
    );

    await box.put(snapshot.id, snapshot);

    expect(box.get('snap')?.totalUsd, 4604.51);
  });
}
