import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/providers/zakat_provider.dart';
import 'package:moniz/services/zakat_engine.dart';
import 'package:moniz/theme/app_theme.dart';
import 'package:moniz/widgets/zakat_mark_paid_button.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_markpaid_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(AssetTagAdapter());
    Hive.registerAdapter(AssetAdapter());
    Hive.registerAdapter(ZakatScheduleModeAdapter());
    Hive.registerAdapter(NisabStandardAdapter());
    Hive.registerAdapter(ZakatSettingsAdapter());
    Hive.registerAdapter(ZakatPaymentRecordAdapter());
    Hive.registerAdapter(MetalPriceSnapshotAdapter());
    await Hive.openBox<ZakatSettings>('zakatSettings');
    await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
    // The confirmation now quotes the amount in the display currency.
    await Hive.openBox<MetalPriceSnapshot>('metalPrices');
    await Hive.openBox<dynamic>('uiPreferences');
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  testWidgets('asks before recording, and cancelling records nothing', (
    tester,
  ) async {
    final notifier = _RecordingZakatNotifier();
    await tester.pumpWidget(_host(notifier));
    await tester.pump();

    await tester.tap(find.byKey(const Key('mark_zakat_paid')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Record this zakat payment?'), findsOneWidget);
    expect(find.textContaining('starts a new lunar year'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    // The amount is named so it can be checked before committing.
    expect(find.textContaining(r'$1,250.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel_zakat_payment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(notifier.recorded, isEmpty);
    expect(find.text('Record this zakat payment?'), findsNothing);
  });

  testWidgets('confirming records the payment', (tester) async {
    final notifier = _RecordingZakatNotifier();
    await tester.pumpWidget(_host(notifier));
    await tester.pump();

    await tester.tap(find.byKey(const Key('mark_zakat_paid')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('confirm_zakat_payment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(notifier.recorded, hasLength(1));
    expect(notifier.recorded.single.amountDueUsd, 1250);
  });
}

Widget _host(_RecordingZakatNotifier notifier) {
  return ProviderScope(
    overrides: [zakatProvider.overrideWith((ref) => notifier)],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(child: ZakatMarkPaidButton(result: _due())),
      ),
    ),
  );
}

ZakatResult _due() {
  return ZakatEngine.calculate(
    assets: [
      Asset(
        id: 'cash',
        type: AssetType.cash,
        amount: 50000,
        unit: 'USD',
        boughtDate: DateTime(2025, 1, 1),
      ),
    ],
    prices: MetalPriceSnapshot(
      goldPerGramUsd: 100,
      silverPerGramUsd: 1,
      priceTimestamp: DateTime.utc(2025, 1, 1),
      fetchedAt: DateTime.utc(2025, 1, 1),
    ),
    settings: const ZakatSettings(
      scheduleMode: ZakatScheduleMode.individualDueDates,
    ),
    payments: const {},
    today: DateTime(2026, 6, 1),
  );
}

/// Captures payments instead of writing to Hive: a write issued from inside a
/// tap handler never settles in the fake-async zone.
class _RecordingZakatNotifier extends ZakatNotifier {
  _RecordingZakatNotifier()
    : super(
        settingsBox: Hive.box<ZakatSettings>('zakatSettings'),
        paymentBox: Hive.box<ZakatPaymentRecord>('zakatPayments'),
      );

  final recorded = <ZakatResult>[];

  @override
  Future<void> recordPayment(ZakatResult result, DateTime paidAt) async {
    recorded.add(result);
  }
}
