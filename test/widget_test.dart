import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/portfolio_snapshot.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/providers/metal_price_provider.dart';
import 'package:moniz/providers/app_lock_provider.dart';
import 'package:moniz/services/app_lock_service.dart';
import 'package:moniz/services/biometric_auth_service.dart';
import 'package:moniz/services/metal_price_service.dart';
import 'package:moniz/ui/kinetic/kinetic_widgets.dart';
import 'package:moniz/widgets/asset_form_dialog.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_widget_test_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(AssetTagAdapter());
    Hive.registerAdapter(AssetAdapter());
    Hive.registerAdapter(MetalPriceSnapshotAdapter());
    Hive.registerAdapter(ZakatScheduleModeAdapter());
    Hive.registerAdapter(NisabStandardAdapter());
    Hive.registerAdapter(ZakatSettingsAdapter());
    Hive.registerAdapter(ZakatPaymentRecordAdapter());
    Hive.registerAdapter(PortfolioSnapshotAdapter());
    await Hive.openBox<Asset>('assets');
    await Hive.openBox<MetalPriceSnapshot>('metalPrices');
    await Hive.openBox<ZakatSettings>('zakatSettings');
    await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
    await Hive.openBox<PortfolioSnapshot>('portfolioSnapshots');
    await Hive.openBox<dynamic>('uiPreferences');
  });

  setUp(() async {
    await Hive.box<Asset>('assets').clear();
    await Hive.box<MetalPriceSnapshot>('metalPrices').clear();
    await Hive.box<ZakatSettings>('zakatSettings').clear();
    await Hive.box<ZakatPaymentRecord>('zakatPayments').clear();
    await Hive.box<PortfolioSnapshot>('portfolioSnapshots').clear();
    await Hive.box<dynamic>('uiPreferences').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('shows the empty persisted assets dashboard', (tester) async {
    await tester.pumpWidget(_buildApp());
    await _pumpKinetic(tester);

    expect(find.text('WEALTH'), findsOneWidget);
    expect(find.text('TOTAL WEALTH'), findsOneWidget);
    await tester.tap(find.byKey(const Key('holdings_nav')));
    await _pumpKinetic(tester);
    expect(find.text('NO ASSETS YET'), findsOneWidget);
  });

  testWidgets('fetches metals on startup and exposes refresh in settings', (
    tester,
  ) async {
    final service = _RecordingUnavailableMetalPriceService();
    await tester.pumpWidget(_buildApp(service: service));
    await _pumpKinetic(tester);

    expect(service.callCount, 1);
    expect(find.byKey(const Key('refresh_metal_prices')), findsNothing);

    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('refresh_metal_prices')),
      300,
    );
    expect(find.byKey(const Key('refresh_metal_prices')), findsOneWidget);
    expect(
      find.text('TAP REFRESH TO LOAD GOLD AND SILVER PRICES.'),
      findsOneWidget,
    );
  });

  testWidgets('shows cached metal prices and values a metal holding', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'gold',
        const Asset(
          id: 'gold',
          type: AssetType.gold,
          amount: 10,
          unit: 'g',
          purity: 50,
          tag: AssetTag.emergency,
        ),
      );
      await Hive.box<MetalPriceSnapshot>('metalPrices').put(
        'latest_usd_gram_prices',
        MetalPriceSnapshot(
          goldPerGramUsd: 90,
          silverPerGramUsd: 1.1,
          priceTimestamp: DateTime.utc(2026, 5, 27, 10),
          fetchedAt: DateTime.utc(2026, 5, 27, 10),
        ),
      );
    });

    await tester.pumpWidget(_buildApp());
    await _pumpKinetic(tester);

    expect(find.text('450.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    await tester.scrollUntilVisible(find.text('90.00'), 300);
    expect(find.text('90.00'), findsOneWidget);
    expect(find.textContaining('CACHED PRICE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dashboard_nav')));
    await _pumpKinetic(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('portfolio_pie_chart')),
      300,
    );
    expect(find.byKey(const Key('portfolio_pie_chart')), findsOneWidget);
    await tester.tap(find.byKey(const Key('holdings_nav')));
    await _pumpKinetic(tester);
    expect(find.byKey(const Key('asset_tag_chip_gold')), findsOneWidget);
  });

  testWidgets('formats large dashboard and ledger numbers with commas', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'cash',
        const Asset(
          id: 'cash',
          type: AssetType.cash,
          amount: 1234567.89,
          unit: 'USD',
        ),
      );
    });

    await tester.pumpWidget(_buildApp());
    await _pumpKinetic(tester);

    expect(find.text('1,234,567.89'), findsOneWidget);
    await tester.tap(find.byKey(const Key('holdings_nav')));
    await _pumpKinetic(tester);
    expect(find.text('1,234,567.89'), findsOneWidget);
  });

  testWidgets('adds a gold asset using rich finance fields', (tester) async {
    Asset? submittedAsset;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submittedAsset = await showDialog<Asset>(
                context: context,
                builder: (_) => const AssetFormDialog(),
              );
            },
            child: const Text('Open form'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await _pumpKinetic(tester);
    await tester.tap(find.byKey(const Key('asset_currency_eur')));
    await _pumpKinetic(tester);
    await tester.tap(find.byKey(const Key('asset_type_gold')));
    await _pumpKinetic(tester);
    await tester.ensureVisible(find.byKey(const Key('asset_tag_gift')));
    await tester.tap(find.byKey(const Key('asset_tag_gift')));
    await _pumpKinetic(tester);

    expect(find.text('WEIGHT (GRAMS)'), findsOneWidget);
    expect(find.text('PURITY'), findsOneWidget);
    expect(find.text('24K'), findsOneWidget);
    expect(find.text('22K'), findsOneWidget);
    expect(find.text('18K'), findsOneWidget);
    expect(find.text('HOLDING START DATE'), findsOneWidget);
    expect(find.text('THIS ASSET HAS BEEN SOLD'), findsOneWidget);
    expect(find.text('SOLD DATE'), findsNothing);

    await tester.enterText(find.byKey(const Key('asset_amount_field')), '30.5');
    await tester.ensureVisible(find.byKey(const Key('asset_purity_gold_24k')));
    await tester.tap(find.byKey(const Key('asset_purity_gold_24k')));
    await tester.enterText(
      find.byKey(const Key('asset_notes_field')),
      'Wedding gold',
    );
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await _pumpKinetic(tester);

    expect(submittedAsset?.type, AssetType.gold);
    expect(submittedAsset?.amount, 30.5);
    expect(submittedAsset?.unit, 'g');
    expect(submittedAsset?.currency, 'EUR');
    expect(submittedAsset?.tag, AssetTag.gift);
    expect(submittedAsset?.purity, 99.9);
    expect(submittedAsset?.boughtPrice, isNull);
    expect(submittedAsset?.soldDate, isNull);
    expect(submittedAsset?.note, 'Wedding gold');
  });

  testWidgets('saves an active gold purchase without sale details', (
    tester,
  ) async {
    final asset = Asset(
      id: 'active-gold',
      type: AssetType.gold,
      amount: 15,
      unit: 'g',
      purity: 99.9,
      boughtDate: DateTime(2025, 1, 1),
      boughtPrice: 1200,
    );
    Asset? submittedAsset;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submittedAsset = await showDialog<Asset>(
                context: context,
                builder: (_) => AssetFormDialog(asset: asset),
              );
            },
            child: const Text('Edit active gold'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit active gold'));
    await _pumpKinetic(tester);

    expect(find.text('SOLD DATE'), findsNothing);
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await _pumpKinetic(tester);

    expect(submittedAsset?.boughtPrice, 1200);
    expect(submittedAsset?.soldDate, isNull);
    expect(submittedAsset?.soldPrice, isNull);
  });

  testWidgets('only offers USD EUR and AED for new assets', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AssetFormDialog()));

    expect(find.text('USD'), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);
    expect(find.text('AED'), findsOneWidget);
    expect(find.text('LBP'), findsNothing);
    expect(find.text('SAR'), findsNothing);
  });

  testWidgets('offers only supported new asset types and silver purity', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AssetFormDialog()));

    expect(find.byKey(const Key('asset_type_cash')), findsOneWidget);
    expect(find.byKey(const Key('asset_type_gold')), findsOneWidget);
    expect(find.byKey(const Key('asset_type_silver')), findsOneWidget);
    expect(find.text('BANK SAVINGS'), findsNothing);

    await tester.tap(find.byKey(const Key('asset_type_silver')));
    await _pumpKinetic(tester);

    await tester.ensureVisible(
      find.byKey(const Key('asset_purity_silver_995')),
    );
    expect(find.byKey(const Key('asset_purity_silver_995')), findsOneWidget);
    expect(find.text('24K'), findsNothing);
    expect(find.text('22K'), findsNothing);
    expect(find.text('18K'), findsNothing);
  });

  testWidgets('offers optional brutalist asset tags', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AssetFormDialog()));

    expect(find.byKey(const Key('asset_tag_none')), findsOneWidget);
    expect(find.byKey(const Key('asset_tag_freelance')), findsOneWidget);
    expect(find.byKey(const Key('asset_tag_emergency')), findsOneWidget);
    expect(find.byKey(const Key('asset_tag_gift')), findsOneWidget);
    expect(find.byKey(const Key('asset_tag_salary')), findsOneWidget);
    expect(find.byKey(const Key('asset_tag_business_profit')), findsOneWidget);
  });

  testWidgets('opens zakat breakdown with payment mode and nisab settings', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await _pumpKinetic(tester);

    await tester.tap(find.byKey(const Key('zakat_nav')));
    await _pumpKinetic(tester);

    expect(find.text('DUE / NISAB'), findsOneWidget);
    expect(find.text('PAY EACH RAMADAN'), findsOneWidget);
    expect(find.text('SILVER NISAB'), findsWidgets);
    expect(find.byKey(const Key('select_ramadan_due_date')), findsOneWidget);
  });

  testWidgets('navigates between dashboard holdings and settings pages', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await _pumpKinetic(tester);

    expect(find.text('WEALTH / LIVE POSITION'), findsOneWidget);

    await tester.tap(find.byKey(const Key('holdings_nav')));
    await _pumpKinetic(tester);
    expect(
      find.text('Add, edit, and scan asset records without visual fog.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    expect(find.text('MODE / PRICES'), findsOneWidget);
    expect(find.text('THEME MODE'), findsOneWidget);
  });

  testWidgets('persists the kinetic theme mode toggle', (tester) async {
    await tester.pumpWidget(_buildApp());
    await _pumpKinetic(tester);

    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    expect(find.text('DARK / DEFAULT'), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme_mode_toggle')));
    await _pumpKinetic(tester);

    expect(Hive.box<dynamic>('uiPreferences').get('themeMode'), 'light');
    expect(find.text('LIGHT / INVERTED'), findsOneWidget);
  });

  testWidgets('dashboard filters holdings by tag', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').putAll({
        'salary': const Asset(
          id: 'salary',
          type: AssetType.cash,
          amount: 100,
          unit: 'USD',
          tag: AssetTag.salary,
        ),
        'gift': const Asset(
          id: 'gift',
          type: AssetType.cash,
          amount: 50,
          unit: 'USD',
          tag: AssetTag.gift,
        ),
      });
    });
    await tester.pumpWidget(_buildApp());
    await _pumpKinetic(tester);

    expect(find.text('150.00'), findsOneWidget);
    tester
        .widget<FilterBlock>(find.byKey(const Key('filter_tag_salary')))
        .onTap();
    await _pumpKinetic(tester);

    expect(find.text('SHOWING 1 OF 2 HOLDINGS'), findsOneWidget);
    expect(find.text('FILTERED WEALTH'), findsOneWidget);
    expect(find.text('100.00'), findsOneWidget);
  });

  testWidgets('dashboard displays trend and paid vs now position card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'active-gold',
        const Asset(
          id: 'active-gold',
          type: AssetType.gold,
          amount: 5,
          unit: 'g',
          currency: 'USD',
          purity: 99.9,
          boughtPrice: 200,
        ),
      );
      await Hive.box<MetalPriceSnapshot>('metalPrices').put(
        'latest_usd_gram_prices',
        MetalPriceSnapshot(
          goldPerGramUsd: 55,
          silverPerGramUsd: 1.1,
          priceTimestamp: DateTime.utc(2026, 5, 27, 10),
          fetchedAt: DateTime.utc(2026, 5, 27, 10),
        ),
      );
      await Hive.box<PortfolioSnapshot>('portfolioSnapshots').putAll({
        'first': PortfolioSnapshot(
          id: 'first',
          capturedAt: DateTime(2026, 1, 1),
          totalUsd: 1000,
          cashUsd: 1000,
          bankSavingsUsd: 0,
          goldUsd: 0,
          silverUsd: 0,
        ),
        'second': PortfolioSnapshot(
          id: 'second',
          capturedAt: DateTime(2026, 2, 1),
          totalUsd: 1200,
          cashUsd: 1200,
          bankSavingsUsd: 0,
          goldUsd: 0,
          silverUsd: 0,
        ),
      });
    });
    await tester.pumpWidget(_buildApp());

    await _pumpKinetic(tester);
    expect(find.byKey(const Key('portfolio_jump_30d')), findsOneWidget);
    expect(find.byKey(const Key('portfolio_jump_90d')), findsOneWidget);
    expect(find.byKey(const Key('portfolio_jump_all')), findsOneWidget);
    expect(find.textContaining('30D JUMP'), findsOneWidget);
    expect(find.text('CASH REMOVED'), findsOneWidget);
    expect(find.text('GOLD CHANGE'), findsOneWidget);
    expect(find.byKey(const Key('portfolio_line_chart')), findsOneWidget);
    expect(find.byKey(const Key('paid_vs_now_amount')), findsOneWidget);
  });

  testWidgets('portfolio trend derives cash jumps from dated assets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final olderCashDate = todayDay.subtract(const Duration(days: 35));
    final recentCashDate = todayDay.subtract(const Duration(days: 1));
    final goldDate = todayDay.subtract(const Duration(days: 12));

    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').putAll({
        'older-cash': Asset(
          id: 'older-cash',
          type: AssetType.cash,
          amount: 100,
          unit: 'USD',
          currency: 'USD',
          boughtDate: olderCashDate,
        ),
        'recent-cash': Asset(
          id: 'recent-cash',
          type: AssetType.cash,
          amount: 200,
          unit: 'USD',
          currency: 'USD',
          boughtDate: recentCashDate,
          tag: AssetTag.salary,
        ),
        'gold': Asset(
          id: 'gold',
          type: AssetType.gold,
          amount: 8,
          unit: 'g',
          currency: 'USD',
          purity: 100,
          boughtDate: goldDate,
          boughtPrice: 400,
        ),
      });
      await Hive.box<MetalPriceSnapshot>('metalPrices').put(
        'latest_usd_gram_prices',
        MetalPriceSnapshot(
          goldPerGramUsd: 55,
          silverPerGramUsd: 1.1,
          priceTimestamp: todayDay,
          fetchedAt: todayDay,
        ),
      );
    });

    await tester.pumpWidget(_buildApp());

    await _pumpKinetic(tester);
    expect(find.text('CASH ADDED'), findsOneWidget);
    expect(find.text('GOLD CHANGE'), findsOneWidget);
    expect(find.text(r'+$200'), findsOneWidget);
    expect(find.byKey(const Key('portfolio_line_chart')), findsOneWidget);
  });

  testWidgets('opens transaction history from wealth breakdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(_buildApp());
    await _pumpKinetic(tester);
    await tester.tap(find.byKey(const Key('open_transaction_history')));
    await _pumpKinetic(tester);

    expect(find.text('TRANSACTION HISTORY'), findsOneWidget);
    expect(find.text('PAID VS NOW'), findsOneWidget);
    expect(find.text('NET WORTH SNAPSHOTS'), findsOneWidget);
  });

  testWidgets('edits an existing rich asset', (tester) async {
    final asset = Asset(
      id: 'silver-record',
      type: AssetType.silver,
      amount: 100,
      unit: 'g',
      currency: 'USD',
      purity: 92.5,
      boughtDate: DateTime(2025, 1, 1),
      boughtPrice: 70,
      soldDate: DateTime(2025, 2, 1),
      soldPrice: 85,
    );
    Asset? submittedAsset;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submittedAsset = await showDialog<Asset>(
                context: context,
                builder: (_) => AssetFormDialog(asset: asset),
              );
            },
            child: const Text('Edit form'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit form'));
    await _pumpKinetic(tester);
    await tester.enterText(find.byKey(const Key('asset_amount_field')), '125');
    await tester.enterText(
      find.byKey(const Key('asset_notes_field')),
      'Updated holding',
    );
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await _pumpKinetic(tester);

    expect(submittedAsset?.id, asset.id);
    expect(submittedAsset?.amount, 125);
    expect(submittedAsset?.purity, asset.purity);
    expect(submittedAsset?.boughtDate, asset.boughtDate);
    expect(submittedAsset?.boughtPrice, asset.boughtPrice);
    expect(submittedAsset?.soldDate, asset.soldDate);
    expect(submittedAsset?.soldPrice, asset.soldPrice);
    expect(submittedAsset?.note, 'Updated holding');
  });

  testWidgets('rejects empty negative and nonnumeric amounts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AssetFormDialog()));

    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();
    expect(find.text('Amount is required'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('asset_amount_field')), '-10');
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();
    expect(find.text('Amount must be greater than zero'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('asset_amount_field')), 'abc');
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();
    expect(find.text('Amount must be numeric'), findsOneWidget);
  });

  testWidgets('rejects invalid metal purity and incomplete sale details', (
    tester,
  ) async {
    final asset = Asset(
      id: 'invalid-sale',
      type: AssetType.gold,
      amount: 20,
      unit: 'g',
      purity: 150,
      boughtDate: DateTime(2025, 2, 1),
      soldDate: DateTime(2025, 2, 10),
    );
    await tester.pumpWidget(MaterialApp(home: AssetFormDialog(asset: asset)));

    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();

    expect(find.text('Purity must be between 0 and 100'), findsOneWidget);
    expect(
      find.text('Sold price is required when sold date is set'),
      findsOneWidget,
    );
  });

  testWidgets('rejects inconsistent transaction dates', (tester) async {
    final asset = Asset(
      id: 'invalid-dates',
      type: AssetType.silver,
      amount: 100,
      unit: 'g',
      purity: 92.5,
      boughtDate: DateTime(2025, 3, 10),
      soldDate: DateTime(2025, 3, 1),
      soldPrice: 75,
    );
    await tester.pumpWidget(MaterialApp(home: AssetFormDialog(asset: asset)));

    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();

    expect(find.byKey(const Key('asset_date_error')), findsOneWidget);
    expect(find.text('Sold date cannot be before bought date'), findsOneWidget);
  });

  testWidgets('requires dates for entered transaction prices', (tester) async {
    final asset = Asset(
      id: 'missing-dates',
      type: AssetType.gold,
      amount: 50,
      unit: 'g',
      purity: 99.9,
      boughtPrice: 1500,
      soldPrice: 1900,
    );
    await tester.pumpWidget(MaterialApp(home: AssetFormDialog(asset: asset)));

    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();

    expect(find.text('Select a bought date for this price'), findsOneWidget);
    expect(find.text('Select a sold date for this price'), findsOneWidget);
  });
}

Widget _buildApp({
  MetalPriceService? service,
  MetalPriceHistoryService? historyService,
}) {
  return ProviderScope(
    overrides: [
      appLockStorageProvider.overrideWithValue(_InMemoryAppLockStorage()),
      biometricAuthServiceProvider.overrideWithValue(
        const _UnavailableBiometricAuthService(),
      ),
      metalPriceServiceProvider.overrideWithValue(
        service ?? _UnavailableMetalPriceService(),
      ),
      metalPriceHistoryServiceProvider.overrideWithValue(
        historyService ?? const _UnavailableMetalPriceHistoryService(),
      ),
    ],
    child: const MonizApp(),
  );
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

class _UnavailableBiometricAuthService implements BiometricAuthService {
  const _UnavailableBiometricAuthService();

  @override
  Future<bool> authenticate() async => false;

  @override
  Future<AppBiometricType> availableType() async => AppBiometricType.none;
}

Future<void> _pumpKinetic(WidgetTester tester) {
  return tester.pump(const Duration(milliseconds: 180));
}

class _UnavailableMetalPriceService implements MetalPriceService {
  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    throw const MetalPriceException('Unavailable in widget test.');
  }
}

class _UnavailableMetalPriceHistoryService implements MetalPriceHistoryService {
  const _UnavailableMetalPriceHistoryService();

  @override
  Future<List<MetalPriceSnapshot>> fetchWeeklyAverages({
    required int days,
  }) async {
    throw const MetalPriceException('Unavailable in widget test.');
  }
}

class _RecordingUnavailableMetalPriceService implements MetalPriceService {
  int callCount = 0;

  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    callCount += 1;
    throw const MetalPriceException('Unavailable in startup test.');
  }
}
