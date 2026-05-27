import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/providers/zakat_provider.dart';
import 'package:moniz/services/zakat_engine.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_zakat_test_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(ZakatScheduleModeAdapter());
    Hive.registerAdapter(NisabStandardAdapter());
    Hive.registerAdapter(ZakatSettingsAdapter());
    Hive.registerAdapter(ZakatPaymentRecordAdapter());
  });

  setUp(() async {
    await Hive.openBox<ZakatSettings>('zakatSettings');
    await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
    await Hive.box<ZakatSettings>('zakatSettings').clear();
    await Hive.box<ZakatPaymentRecord>('zakatPayments').clear();
  });

  tearDown(() async {
    await Hive.box<ZakatSettings>('zakatSettings').close();
    await Hive.box<ZakatPaymentRecord>('zakatPayments').close();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test(
    'annual payment advances the next Ramadan due date by a lunar year',
    () async {
      final notifier = ZakatNotifier(
        settingsBox: Hive.box<ZakatSettings>('zakatSettings'),
        paymentBox: Hive.box<ZakatPaymentRecord>('zakatPayments'),
      );
      addTearDown(notifier.dispose);
      await notifier.setRamadanDueDate(DateTime(2026, 3, 1));

      await notifier.recordPayment(
        _result(
          settings: notifier.state,
          includedAssets: const [
            Asset(id: 'cash', type: AssetType.cash, amount: 1000, unit: 'USD'),
          ],
        ),
        DateTime(2026, 3, 1),
      );

      expect(notifier.state.nextRamadanDueDate, DateTime(2027, 2, 18));
      expect(notifier.payments['annual_ramadan']?.amountUsd, 25);
    },
  );

  test('monthly payment records the paid holding for its next hawl', () async {
    final notifier = ZakatNotifier(
      settingsBox: Hive.box<ZakatSettings>('zakatSettings'),
      paymentBox: Hive.box<ZakatPaymentRecord>('zakatPayments'),
    );
    addTearDown(notifier.dispose);
    await notifier.setScheduleMode(ZakatScheduleMode.individualDueDates);

    await notifier.recordPayment(
      _result(
        settings: notifier.state,
        includedAssets: [
          Asset(
            id: 'cash',
            type: AssetType.cash,
            amount: 1000,
            unit: 'USD',
            boughtDate: DateTime(2025, 1, 1),
          ),
        ],
      ),
      DateTime(2026, 1, 1),
    );

    expect(notifier.payments['cash']?.paidAt, DateTime(2026, 1, 1));
    expect(notifier.payments['cash']?.amountUsd, 25);
  });
}

ZakatResult _result({
  required ZakatSettings settings,
  required List<Asset> includedAssets,
}) {
  return ZakatResult(
    settings: settings,
    assessments: includedAssets
        .map(
          (asset) => ZakatAssetAssessment(
            asset: asset,
            valueUsd: asset.amount,
            isIncluded: true,
          ),
        )
        .toList(),
    nisabThresholdUsd: 600,
    eligibleWealthUsd: 1000,
    amountDueUsd: 25,
    canCalculate: true,
    isScheduleDue: true,
  );
}
