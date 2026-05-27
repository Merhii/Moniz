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
import 'package:moniz/services/metal_price_service.dart';
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
  });

  setUp(() async {
    await Hive.box<Asset>('assets').clear();
    await Hive.box<MetalPriceSnapshot>('metalPrices').clear();
    await Hive.box<ZakatSettings>('zakatSettings').clear();
    await Hive.box<ZakatPaymentRecord>('zakatPayments').clear();
    await Hive.box<PortfolioSnapshot>('portfolioSnapshots').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('shows the empty persisted assets dashboard', (tester) async {
    await tester.pumpWidget(_buildApp());

    expect(find.text('Moniz - Dashboard'), findsOneWidget);
    expect(find.text('Total Wealth'), findsOneWidget);
    await tester.tap(find.byKey(const Key('holdings_nav')));
    await tester.pumpAndSettle();
    expect(find.text('No assets yet'), findsOneWidget);
  });

  testWidgets('fetches metals on startup and exposes refresh in settings', (
    tester,
  ) async {
    final service = _RecordingUnavailableMetalPriceService();
    await tester.pumpWidget(_buildApp(service: service));
    await tester.pumpAndSettle();

    expect(service.callCount, 1);
    expect(find.byKey(const Key('refresh_metal_prices')), findsNothing);

    await tester.tap(find.byKey(const Key('settings_nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('refresh_metal_prices')), findsOneWidget);
    expect(
      find.text('Tap refresh to load gold and silver prices.'),
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

    expect(find.text(r'$450.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings_nav')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(r'$90.00 / gram'), 300);
    expect(find.text(r'$90.00 / gram'), findsOneWidget);
    expect(find.textContaining('Cached price'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dashboard_nav')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('portfolio_pie_chart')),
      300,
    );
    expect(find.byKey(const Key('portfolio_pie_chart')), findsOneWidget);
    await tester.tap(find.byKey(const Key('holdings_nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asset_tag_chip_gold')), findsOneWidget);
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('asset_currency_eur')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('asset_type_gold')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('asset_tag_gift')));
    await tester.tap(find.byKey(const Key('asset_tag_gift')));
    await tester.pumpAndSettle();

    expect(find.text('Weight (grams)'), findsOneWidget);
    expect(find.text('Purity'), findsOneWidget);
    expect(find.text('24K'), findsOneWidget);
    expect(find.text('22K'), findsOneWidget);
    expect(find.text('18K'), findsOneWidget);
    expect(find.text('Holding Start Date'), findsOneWidget);
    expect(find.text('This asset has been sold'), findsOneWidget);
    expect(find.text('Sold Date'), findsNothing);

    await tester.enterText(find.byKey(const Key('asset_amount_field')), '30.5');
    await tester.ensureVisible(find.byKey(const Key('asset_purity_gold_24k')));
    await tester.tap(find.byKey(const Key('asset_purity_gold_24k')));
    await tester.enterText(
      find.byKey(const Key('asset_notes_field')),
      'Wedding gold',
    );
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(find.text('Sold Date'), findsNothing);
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pumpAndSettle();

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
    expect(find.text('Bank Savings'), findsNothing);

    await tester.tap(find.byKey(const Key('asset_type_silver')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('asset_purity_silver_995')),
    );
    expect(find.byKey(const Key('asset_purity_silver_995')), findsOneWidget);
    expect(find.text('24K'), findsNothing);
    expect(find.text('22K'), findsNothing);
    expect(find.text('18K'), findsNothing);
  });

  testWidgets('offers optional icon-backed asset tags', (tester) async {
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

    await tester.tap(find.byKey(const Key('settings_nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view_zakat_breakdown')));
    await tester.pumpAndSettle();

    expect(find.text('Zakat Breakdown'), findsOneWidget);
    expect(find.text('Pay each Ramadan'), findsOneWidget);
    expect(find.text('Silver nisab'), findsOneWidget);
    expect(find.byKey(const Key('select_ramadan_due_date')), findsOneWidget);
  });

  testWidgets('navigates between dashboard holdings and settings pages', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());

    expect(
      find.text('Track, compare, and filter your wealth.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('holdings_nav')));
    await tester.pumpAndSettle();
    expect(
      find.text('Add, edit, and organize your asset records.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings_nav')));
    await tester.pumpAndSettle();
    expect(find.text('Zakat Settings & Payments'), findsOneWidget);
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

    expect(find.text(r'$150.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('filter_tag_salary')),
      100,
    );
    await tester.tap(find.byKey(const Key('filter_tag_salary')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 2 holdings'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Filtered Wealth'), -300);
    expect(find.text('Filtered Wealth'), findsOneWidget);
    expect(find.text(r'$100.00'), findsOneWidget);
  });

  testWidgets('dashboard displays trend and realized profit loss charts', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'sold-gold',
        Asset(
          id: 'sold-gold',
          type: AssetType.gold,
          amount: 5,
          unit: 'g',
          currency: 'USD',
          purity: 99.9,
          boughtPrice: 200,
          soldDate: DateTime(2026, 1, 1),
          soldPrice: 275,
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

    await tester.scrollUntilVisible(
      find.byKey(const Key('portfolio_line_chart')),
      300,
    );
    expect(find.byKey(const Key('portfolio_line_chart')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('profit_loss_sold-gold')),
      300,
    );
    expect(find.text('+USD 75.00'), findsOneWidget);
  });

  testWidgets('opens transaction history from wealth breakdown', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());

    await tester.scrollUntilVisible(
      find.byKey(const Key('open_transaction_history')),
      300,
    );
    tester
        .widget<OutlinedButton>(
          find.byKey(const Key('open_transaction_history')),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Transaction History'), findsOneWidget);
    expect(find.text('Realized Profit / Loss'), findsOneWidget);
    expect(find.text('Net Worth Snapshots'), findsOneWidget);
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
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('asset_amount_field')), '125');
    await tester.enterText(
      find.byKey(const Key('asset_notes_field')),
      'Updated holding',
    );
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pumpAndSettle();

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

Widget _buildApp({MetalPriceService? service}) {
  return ProviderScope(
    overrides: [
      metalPriceServiceProvider.overrideWithValue(
        service ?? _UnavailableMetalPriceService(),
      ),
    ],
    child: const MonizApp(),
  );
}

class _UnavailableMetalPriceService implements MetalPriceService {
  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
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
