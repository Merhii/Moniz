import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/recurring_entry.dart';
import 'package:moniz/models/portfolio_snapshot.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/providers/asset_provider.dart';
import 'package:moniz/services/currency_converter.dart';
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
    Hive.registerAdapter(MoneyDirectionAdapter());
    Hive.registerAdapter(MoneyCategoryAdapter());
    Hive.registerAdapter(MoneyAccountAdapter());
    Hive.registerAdapter(MoneyEntryAdapter());
    Hive.registerAdapter(RecurrenceFrequencyAdapter());
    Hive.registerAdapter(RecurringEntryAdapter());
    await Hive.openBox<Asset>('assets');
    await Hive.openBox<MetalPriceSnapshot>('metalPrices');
    await Hive.openBox<ZakatSettings>('zakatSettings');
    await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
    await Hive.openBox<PortfolioSnapshot>('portfolioSnapshots');
    await Hive.openBox<dynamic>('uiPreferences');
    await Hive.openBox<MoneyEntry>('moneyEntries');
    await Hive.openBox<MoneyCategory>('moneyCategories');
    await Hive.openBox<MoneyAccount>('moneyAccounts');
    await Hive.openBox<RecurringEntry>('moneyRecurrences');
  });

  setUp(() async {
    await Hive.box<Asset>('assets').clear();
    await Hive.box<MetalPriceSnapshot>('metalPrices').clear();
    await Hive.box<ZakatSettings>('zakatSettings').clear();
    await Hive.box<ZakatPaymentRecord>('zakatPayments').clear();
    await Hive.box<PortfolioSnapshot>('portfolioSnapshots').clear();
    // Display currency and theme live here; leaving them set would carry a
    // preference from one test into the next.
    await Hive.box<dynamic>('uiPreferences').clear();
    await Hive.box<MoneyEntry>('moneyEntries').clear();
    await Hive.box<MoneyCategory>('moneyCategories').clear();
    await Hive.box<MoneyAccount>('moneyAccounts').clear();
    await Hive.box<RecurringEntry>('moneyRecurrences').clear();
    await seedMoneyDefaults();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  testWidgets('shows the empty persisted assets dashboard', (tester) async {
    await _pumpWealth(tester);

    expect(find.text('Wealth'), findsOneWidget);
    expect(find.text('TOTAL WEALTH'), findsOneWidget);
    // With no holdings the dashboard shows its own empty state; there is no
    // separate Ledger tab holding a second one.
    expect(find.byKey(const Key('dashboard_empty_title')), findsOneWidget);
  });

  testWidgets('first run offers a way to add a holding, not empty filters', (
    tester,
  ) async {
    await _pumpWealth(tester);

    expect(find.byKey(const Key('dashboard_empty_title')), findsOneWidget);
    expect(
      find.byKey(const Key('dashboard_add_first_holding')),
      findsOneWidget,
    );

    // Controls that need holdings to mean anything are not shown.
    expect(find.byKey(const Key('filter_type_all')), findsNothing);
    expect(find.byKey(const Key('dashboard_filter_result')), findsNothing);
    expect(find.text('Asset allocation'), findsNothing);

    // And the call to action opens the form.
    final cta = find.byKey(const Key('dashboard_add_first_holding'));
    await tester.ensureVisible(cta);
    await _pumpKinetic(tester);
    await tester.tap(cta);
    await _pumpKinetic(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('asset_amount_field')), findsOneWidget);
  });

  testWidgets('filters and analytics come back once a holding exists', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'cash',
        const Asset(id: 'cash', type: AssetType.cash, amount: 100, unit: 'USD'),
      );
    });

    await _pumpWealth(tester);

    expect(find.byKey(const Key('dashboard_empty_title')), findsNothing);
    expect(find.byKey(const Key('filter_type_all')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_add_first_holding')), findsNothing);
  });

  testWidgets('dashboard fits a compact mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpWealth(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('wealth_hero_total')), findsOneWidget);
    expect(find.byKey(const Key('settings_nav')), findsOneWidget);
  });

  testWidgets('fades the tag filter rail when it runs off a phone screen', (
    tester,
  ) async {
    // The filter rail only appears once there is something to filter.
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'cash',
        const Asset(id: 'cash', type: AssetType.cash, amount: 100, unit: 'USD'),
      );
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpWealth(tester);

    final tagRail = find.ancestor(
      of: find.byKey(const Key('filter_tag_all')),
      matching: find.byType(Scrollable),
    );
    // More tags exist than fit, so the rail really does scroll...
    expect(tester.widget<Scrollable>(tagRail.first).axisDirection, isNotNull);
    expect(
      tester.state<ScrollableState>(tagRail.first).position.extentAfter,
      greaterThan(0),
    );
    // ...and the edge is faded to show it.
    expect(
      find.ancestor(of: tagRail.first, matching: find.byType(ShaderMask)),
      findsWidgets,
    );
  });

  testWidgets('notification app bar action opens notifications', (
    tester,
  ) async {
    await _pumpWealth(tester);

    await tester.tap(find.byKey(const Key('open_notifications')));
    await tester.pump();
    await _pumpKinetic(tester);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.byKey(const Key('close_notifications')), findsOneWidget);

    // The bell used to land on a page reading "Future implementation"; the
    // old assertions passed anyway because they only checked the title and
    // the back button.
    expect(find.text('Future implementation'), findsNothing);
    final page = find.byKey(const Key('notifications_scroll'));
    expect(
      find.descendant(of: page, matching: find.text('Notification interests')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: page,
        matching: find.textContaining('topics you want'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('fetches metals on startup and exposes refresh in settings', (
    tester,
  ) async {
    final service = _RecordingUnavailableMetalPriceService();
    await _pumpWealth(tester, app: _buildApp(service: service));

    expect(service.callCount, 1);
    expect(find.byKey(const Key('refresh_metal_prices')), findsNothing);

    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('refresh_metal_prices')),
      300,
      scrollable: _verticalScrollableIn(const Key('settings_scroll')),
    );
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

    await _pumpWealth(tester);

    expect(find.text('450.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    await tester.scrollUntilVisible(
      find.text('90.00'),
      300,
      scrollable: _verticalScrollableIn(const Key('settings_scroll')),
    );
    expect(find.text('90.00'), findsOneWidget);
    expect(find.textContaining('CACHED PRICE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dashboard_nav')));
    await _pumpKinetic(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('portfolio_pie_chart')),
      300,
      scrollable: _verticalScrollableIn(const Key('dashboard_scroll')),
    );
    expect(find.byKey(const Key('portfolio_pie_chart')), findsOneWidget);
    await _scrollToHolding(tester, const Key('asset_tag_chip_gold'));
    expect(find.byKey(const Key('asset_tag_chip_gold')), findsOneWidget);
  });

  testWidgets('ticker quotes metals in the selected display currency', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<MetalPriceSnapshot>('metalPrices').put(
        'latest_usd_gram_prices',
        MetalPriceSnapshot(
          goldPerGramUsd: 100,
          silverPerGramUsd: 1,
          priceTimestamp: DateTime.utc(2026, 5, 27, 10),
          fetchedAt: DateTime.utc(2026, 5, 27, 10),
        ),
      );
    });

    await _pumpWealth(tester);
    expect(find.textContaining('LIVE GOLD \$100.00 / G'), findsWidgets);
  });

  testWidgets('metal row does not restate a currency the amounts already show', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<dynamic>('uiPreferences').put('displayCurrency', 'AED');
      await Hive.box<Asset>('assets').put(
        'gold',
        const Asset(
          id: 'gold',
          type: AssetType.gold,
          amount: 10,
          unit: 'g',
          purity: 50,
          currency: 'USD',
          boughtPrice: 1000,
        ),
      );
      await Hive.box<MetalPriceSnapshot>('metalPrices').put(
        'latest_usd_gram_prices',
        MetalPriceSnapshot(
          goldPerGramUsd: 100,
          silverPerGramUsd: 1,
          priceTimestamp: DateTime.utc(2026, 5, 27, 10),
          fetchedAt: DateTime.utc(2026, 5, 27, 10),
        ),
      );
    });

    await _pumpWealth(tester);
    await _scrollToHolding(tester, const Key('asset_value_gold'));

    // The worth is in the display currency, the bought price in the currency
    // it was recorded in. Both say so themselves, so a separate "Prices in
    // USD" only reads as a contradiction of the AED line above it.
    final worth = tester.widget<KineticText>(
      find.byKey(const Key('asset_value_gold')),
    );
    expect(worth.text, 'Worth AED 1,836.25');
    final detail = tester.widget<KineticText>(
      find.byKey(const Key('asset_metal_detail_gold')),
    );
    expect(detail.text, '50.0% purity / Bought \$1,000.00');
    expect(find.textContaining('Prices in'), findsNothing);
  });

  testWidgets('display currency is set in Settings, not on the dashboard', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'cash',
        const Asset(id: 'cash', type: AssetType.cash, amount: 100, unit: 'USD'),
      );
    });

    await _pumpWealth(tester);

    // The dashboard used to carry a currency pill under the hero total. It sat
    // beside the number it changed, which made a preference look like a filter.
    for (final currency in CurrencyConverter.supportedCurrencies) {
      expect(
        find.byKey(Key('home_display_currency_$currency')),
        findsNothing,
        reason: '$currency chip should not be on the dashboard',
      );
    }

    // It lives in one place now, with the rest of the preferences.
    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    final dropdown = find.byKey(const Key('settings_currency_dropdown'));
    await tester.scrollUntilVisible(
      dropdown,
      300,
      scrollable: _verticalScrollableIn(const Key('settings_scroll')),
    );
    expect(dropdown, findsOneWidget);
    expect(
      tester.widget<DropdownButton<String>>(dropdown).items,
      hasLength(CurrencyConverter.supportedCurrencies.length),
    );
  });

  testWidgets('ticker follows a stored non-USD display currency', (
    tester,
  ) async {
    // Seeded rather than tapped: setCurrency writes to Hive, and a write
    // issued inside the fake-async zone never settles.
    await tester.runAsync(() async {
      await Hive.box<dynamic>('uiPreferences').put('displayCurrency', 'AED');
      await Hive.box<MetalPriceSnapshot>('metalPrices').put(
        'latest_usd_gram_prices',
        MetalPriceSnapshot(
          goldPerGramUsd: 100,
          silverPerGramUsd: 1,
          priceTimestamp: DateTime.utc(2026, 5, 27, 10),
          fetchedAt: DateTime.utc(2026, 5, 27, 10),
        ),
      );
    });

    await _pumpWealth(tester);

    // 100 USD/g at the 3.6725 peg.
    expect(find.textContaining('LIVE GOLD AED 367.25 / G'), findsWidgets);
    expect(find.textContaining('LIVE GOLD \$'), findsNothing);
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

    await _pumpWealth(tester);

    // The hero total, and then the holding's own line further down.
    expect(find.text('1,234,567.89'), findsOneWidget);
    // A USD holding shown in USD needs no converted line, so the row is
    // reached by a control it does have.
    await _scrollToHolding(tester, const Key('edit_asset_cash'));
    expect(find.textContaining('1,234,567.89'), findsWidgets);
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

    expect(find.text('Weight (grams)'), findsOneWidget);
    expect(find.text('Purity'), findsOneWidget);
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
    expect(find.text('Bank Savings'), findsNothing);

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

  testWidgets('zakat tab shows payment mode and nisab settings', (
    tester,
  ) async {
    await _pumpWealth(tester);

    await tester.tap(find.byKey(const Key('zakat_nav')));
    await _pumpKinetic(tester);

    expect(find.text('Due and nisab'), findsOneWidget);
    expect(find.text('Pay each Ramadan'), findsOneWidget);
    expect(find.text('Silver nisab'), findsWidgets);
    expect(find.byKey(const Key('select_ramadan_due_date')), findsOneWidget);
  });

  testWidgets('each row edits its own holding, even with several on screen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'gold',
        const Asset(
          id: 'gold',
          type: AssetType.gold,
          amount: 20,
          unit: 'g',
          purity: 99.9,
        ),
      );
      await Hive.box<Asset>('assets').put(
        'savings',
        const Asset(
          id: 'savings',
          type: AssetType.cash,
          amount: 4200,
          unit: 'USD',
        ),
      );
    });

    await _pumpWealth(tester);
    // Every row has its own Edit, so the label alone cannot say which one a
    // test or the driver means. The key can — and each row is reachable by it
    // even when the list is long enough that rows build lazily.
    await _scrollToHolding(tester, const Key('edit_asset_gold'));
    expect(find.byKey(const Key('edit_asset_gold')), findsOneWidget);
    expect(find.text('Edit'), findsWidgets);

    await _scrollToHolding(tester, const Key('edit_asset_savings'));
    expect(find.byKey(const Key('edit_asset_savings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_asset_savings')));
    await tester.pumpAndSettle();
    final amount = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('asset_amount_field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(amount.controller.text, '4200');
  });

  testWidgets('the zakat schedule and nisab pickers can be addressed by key', (
    tester,
  ) async {
    await _pumpWealth(tester);
    await tester.tap(find.byKey(const Key('zakat_nav')));
    await _pumpKinetic(tester);

    // 'Silver nisab' already appears more than once on this page, so a text
    // finder cannot reach the picker. Flutter Driver rejects anything but an
    // exact single match.
    expect(find.text('Silver nisab'), findsWidgets);

    final schedule = tester.widget<KineticDropdown<ZakatScheduleMode>>(
      find.byKey(const Key('zakat_schedule_mode')),
    );
    expect(schedule.value, ZakatScheduleMode.ramadanAnnual);
    expect(schedule.items, ZakatScheduleMode.values);

    final nisab = tester.widget<KineticDropdown<NisabStandard>>(
      find.byKey(const Key('zakat_nisab_standard')),
    );
    expect(nisab.value, NisabStandard.silver);
    expect(nisab.items, NisabStandard.values);
  });

  testWidgets('navigates between wealth, zakat and settings', (
    tester,
  ) async {
    await _pumpWealth(tester);

    expect(find.text('Live position'), findsOneWidget);

    // Wealth carries the holdings now, so with none it shows their empty state
    // instead of a second tab doing it.
    expect(find.byKey(const Key('dashboard_add_first_holding')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Theme mode'), findsOneWidget);
  });

  testWidgets('zakat is quoted in the display currency everywhere', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<dynamic>('uiPreferences').put('displayCurrency', 'AED');
      // The default schedule is Ramadan-annual with no date, under which
      // nothing is ever assessed.
      await Hive.box<ZakatSettings>('zakatSettings').put(
        'settings',
        const ZakatSettings(scheduleMode: ZakatScheduleMode.individualDueDates),
      );
      await Hive.box<Asset>('assets').put(
        'cash',
        Asset(
          id: 'cash',
          type: AssetType.cash,
          amount: 50000,
          unit: 'USD',
          boughtDate: DateTime(2020, 1, 1),
        ),
      );
      await Hive.box<MetalPriceSnapshot>('metalPrices').put(
        'latest_usd_gram_prices',
        MetalPriceSnapshot(
          goldPerGramUsd: 100,
          silverPerGramUsd: 1,
          priceTimestamp: DateTime.utc(2026, 5, 27),
          fetchedAt: DateTime.utc(2026, 5, 27),
        ),
      );
    });

    await _pumpWealth(tester);

    // 50,000 USD -> 1,250 USD zakat -> AED 4,590.63 at the peg. The dashboard
    // already converts.
    expect(find.text('4,590.63'), findsWidgets);

    await tester.tap(find.byKey(const Key('zakat_nav')));
    await _pumpKinetic(tester);

    // The Zakat tab must not disagree with the dashboard about the same
    // obligation.
    final amountDue = tester
        .widgetList<KineticNumber>(find.byKey(const Key('zakat_amount_due')))
        .first;
    expect(amountDue.currency, 'AED');
    expect(amountDue.value, 'AED 4,590.63');
  });

  testWidgets('opens the About tab from bottom navigation', (tester) async {
    await _pumpWealth(tester);

    await tester.tap(find.byKey(const Key('about_nav')));
    await _pumpKinetic(tester);

    expect(find.text('About MONIZ'), findsOneWidget);
    expect(find.text('APP VERSION'), findsOneWidget);
  });

  testWidgets('dashboard filters holdings by tag', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
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
    await _pumpWealth(tester);

    expect(find.text('150.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter_tag_salary')));
    await _pumpKinetic(tester);

    expect(find.text('Showing 1 of 2 holdings'), findsOneWidget);
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
    await _pumpWealth(tester);
    expect(find.byKey(const Key('portfolio_jump_30d')), findsOneWidget);
    expect(find.byKey(const Key('portfolio_jump_90d')), findsOneWidget);
    expect(find.byKey(const Key('portfolio_jump_all')), findsOneWidget);
    expect(find.textContaining('30D jump'), findsOneWidget);
    expect(find.text('Cash removed'), findsOneWidget);
    expect(find.text('Gold change'), findsOneWidget);
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

    await _pumpWealth(tester);
    expect(find.text('Cash added'), findsOneWidget);
    expect(find.text('Gold change'), findsOneWidget);
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
    await _pumpWealth(tester);
    await tester.tap(find.byKey(const Key('open_transaction_history')));
    await _pumpKinetic(tester);

    expect(find.text('Transaction history'), findsOneWidget);
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

  testWidgets('selling a holding offers to record the proceeds', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'gold',
        Asset(
          id: 'gold',
          type: AssetType.gold,
          amount: 20,
          unit: 'g',
          purity: 99.9,
          boughtDate: DateTime(2024, 1, 1),
        ),
      );
    });

    final notifier = _RecordingAssetNotifier();
    await _pumpWealth(
      tester,
      app: _buildApp(
        overrides: [assetProvider.overrideWith((ref) => notifier)],
      ),
    );
    await _scrollToHolding(tester, const Key('edit_asset_gold'));

    await tester.tap(find.byKey(const Key('edit_asset_gold')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asset_amount_field')), findsOneWidget);

    final soldToggle = find.byKey(const Key('asset_is_sold_toggle'));
    await tester.ensureVisible(soldToggle);
    await tester.tap(soldToggle);
    await _pumpKinetic(tester);

    final soldDate = find.byKey(const Key('asset_sold_date_field'));
    await tester.ensureVisible(soldDate);
    await tester.tap(soldDate);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('asset_sold_price_field')),
      '2000',
    );
    final save = find.byKey(const Key('asset_save_button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _pumpKinetic(tester);
    await _pumpKinetic(tester);

    // Without this the $2,000 simply leaves the ledger.
    expect(find.text('Record what you received?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('record_sale_proceeds')));
    await _pumpKinetic(tester);

    expect(notifier.added, hasLength(1));
    expect(notifier.added.single.type, AssetType.cash);
    expect(notifier.added.single.amount, 2000);
    expect(notifier.added.single.boughtDate, DateTime(2024, 1, 1));
  });

  testWidgets('and takes no for an answer', (tester) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'gold',
        Asset(
          id: 'gold',
          type: AssetType.gold,
          amount: 20,
          unit: 'g',
          purity: 99.9,
          boughtDate: DateTime(2024, 1, 1),
        ),
      );
    });

    final notifier = _RecordingAssetNotifier();
    await _pumpWealth(
      tester,
      app: _buildApp(
        overrides: [assetProvider.overrideWith((ref) => notifier)],
      ),
    );
    await _scrollToHolding(tester, const Key('edit_asset_gold'));
    await tester.tap(find.byKey(const Key('edit_asset_gold')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asset_amount_field')), findsOneWidget);

    final soldToggle = find.byKey(const Key('asset_is_sold_toggle'));
    await tester.ensureVisible(soldToggle);
    await tester.tap(soldToggle);
    await _pumpKinetic(tester);
    final soldDate = find.byKey(const Key('asset_sold_date_field'));
    await tester.ensureVisible(soldDate);
    await tester.tap(soldDate);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('asset_sold_price_field')),
      '2000',
    );
    final save = find.byKey(const Key('asset_save_button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _pumpKinetic(tester);
    await _pumpKinetic(tester);

    await tester.tap(find.byKey(const Key('skip_sale_proceeds')));
    await _pumpKinetic(tester);

    expect(notifier.added, isEmpty);
  });

  testWidgets('deleting a holding asks first and can be cancelled', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<Asset>('assets').put(
        'doomed',
        const Asset(
          id: 'doomed',
          type: AssetType.cash,
          amount: 4321,
          unit: 'USD',
        ),
      );
    });

    // Storage for removeAsset is covered in asset_provider_test.dart; this
    // notifier keeps the Hive write out of the fake-async zone so the tap
    // resolves synchronously.
    final notifier = _RecordingAssetNotifier();

    await _pumpWealth(
      tester,
      app: _buildApp(
        overrides: [assetProvider.overrideWith((ref) => notifier)],
      ),
    );
    await _scrollToHolding(tester, const Key('delete_asset_doomed'));

    // Delete no longer removes anything on its own.
    await tester.tap(find.byKey(const Key('delete_asset_doomed')));
    await _pumpKinetic(tester);
    expect(find.text('Delete this holding?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    // Cancelling dismisses the dialog and keeps the holding.
    await tester.tap(find.byKey(const Key('cancel_delete_asset')));
    await _pumpKinetic(tester);
    expect(find.text('Delete this holding?'), findsNothing);
    expect(notifier.removed, isEmpty);
    expect(find.byKey(const Key('delete_asset_doomed')), findsOneWidget);

    // Confirming removes the row.
    await tester.tap(find.byKey(const Key('delete_asset_doomed')));
    await _pumpKinetic(tester);
    await tester.tap(find.byKey(const Key('confirm_delete_asset')));
    await _pumpKinetic(tester);
    expect(notifier.removed, ['doomed']);
    expect(find.byKey(const Key('delete_asset_doomed')), findsNothing);
  });

  testWidgets('warns while a holding has no start date', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AssetFormDialog()));
    await tester.pump();

    final note = find.byKey(const Key('asset_missing_start_date_note'));
    expect(note, findsOneWidget);
    expect(find.textContaining('left out of zakat'), findsOneWidget);

    // An asset that already has a start date is not nagged.
    await tester.pumpWidget(
      MaterialApp(
        home: AssetFormDialog(
          // A fresh key so the form rebuilds its state from this asset
          // instead of reusing the blank one above.
          key: const ValueKey('dated-form'),
          asset: Asset(
            id: 'dated',
            type: AssetType.cash,
            amount: 100,
            unit: 'USD',
            boughtDate: DateTime(2025, 1, 1),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(note, findsNothing);
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

  testWidgets('rejects amounts that overflow to infinity or NaN', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AssetFormDialog()));

    // A literal that parses to double.infinity would otherwise be stored and
    // poison every downstream total with Infinity/NaN.
    await tester.enterText(
      find.byKey(const Key('asset_amount_field')),
      '1e400',
    );
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();
    expect(find.text('Amount is too large'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('asset_amount_field')),
      'Infinity',
    );
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();
    expect(find.text('Amount is too large'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('asset_amount_field')), 'NaN');
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();
    expect(find.text('Amount must be numeric'), findsOneWidget);
  });

  testWidgets('rejects a non-finite bought price', (tester) async {
    final asset = Asset(
      id: 'overflowing-price',
      type: AssetType.gold,
      amount: 50,
      unit: 'g',
      purity: 99.9,
      boughtDate: DateTime(2025, 2, 1),
    );
    await tester.pumpWidget(MaterialApp(home: AssetFormDialog(asset: asset)));

    await tester.enterText(
      find.byKey(const Key('asset_bought_price_field')),
      '1e400',
    );
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump();
    expect(find.text('Bought price is too large'), findsOneWidget);
  });

  testWidgets('gold purity must be chosen, silver picks its only option', (
    tester,
  ) async {
    Asset? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submitted = await showDialog<Asset>(
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

    await tester.tap(find.byKey(const Key('asset_type_gold')));
    await _pumpKinetic(tester);
    await tester.enterText(find.byKey(const Key('asset_amount_field')), '20');
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await _pumpKinetic(tester);

    // Gold used to arrive pre-set to 24K, so a 22K holding saved as 24K
    // unless the owner noticed and changed it.
    expect(submitted, isNull);
    expect(find.text('Select a purity'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('asset_purity_gold_22k')));
    await tester.tap(find.byKey(const Key('asset_purity_gold_22k')));
    await _pumpKinetic(tester);
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await _pumpKinetic(tester);
    expect(submitted?.purity, 91.7);
  });

  testWidgets('silver still picks its single purity automatically', (
    tester,
  ) async {
    Asset? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submitted = await showDialog<Asset>(
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

    await tester.tap(find.byKey(const Key('asset_type_silver')));
    await _pumpKinetic(tester);
    await tester.enterText(find.byKey(const Key('asset_amount_field')), '200');
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await _pumpKinetic(tester);

    // One option means there is nothing to ask about.
    expect(submitted?.purity, 99.5);
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

  testWidgets('marking sold with no details is refused, not silently dropped', (
    tester,
  ) async {
    final gold = Asset(
      id: 'gold',
      type: AssetType.gold,
      amount: 20,
      unit: 'g',
      purity: 99.9,
      boughtDate: DateTime(2024, 1, 1),
    );
    Asset? submitted;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submitted = await showDialog<Asset>(
                context: context,
                builder: (_) => AssetFormDialog(asset: gold),
              );
              closed = true;
            },
            child: const Text('Open form'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await _pumpKinetic(tester);

    await tester.ensureVisible(find.byKey(const Key('asset_is_sold_toggle')));
    await tester.tap(find.byKey(const Key('asset_is_sold_toggle')));
    await _pumpKinetic(tester);
    await tester.ensureVisible(find.byKey(const Key('asset_save_button')));
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await _pumpKinetic(tester);

    // Previously this saved with soldDate null, so the holding was not sold
    // and nothing said so.
    expect(closed, isFalse);
    expect(submitted, isNull);
    expect(find.byKey(const Key('asset_date_error')), findsOneWidget);
    expect(find.textContaining('Select a sold date'), findsOneWidget);
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

  testWidgets('persists the kinetic theme mode toggle', (tester) async {
    await _pumpWealth(tester);

    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pumpKinetic(tester);
    expect(find.text('Dark mode'), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme_mode_toggle')));
    await _pumpKinetic(tester);

    expect(Hive.box<dynamic>('uiPreferences').get('themeMode'), 'light');
    expect(find.text('Light mode'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Widget _buildApp({
  MetalPriceService? service,
  MetalPriceHistoryService? historyService,
  List<Override> overrides = const [],
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
      ...overrides,
    ],
    child: const MonizApp(),
  );
}

/// Records deletions instead of writing to Hive, so widget tests can drive the
/// delete flow without a disk write that never settles under fake async.
class _RecordingAssetNotifier extends AssetNotifier {
  final removed = <String>[];
  final added = <Asset>[];
  final updated = <Asset>[];

  @override
  Future<void> removeAsset(String id) async {
    removed.add(id);
    state = state.where((asset) => asset.id != id).toList();
  }

  @override
  Future<void> addAsset(Asset asset) async {
    added.add(asset);
    state = [...state, asset];
  }

  @override
  Future<void> updateAsset(Asset asset) async {
    updated.add(asset);
    state = [
      for (final existing in state)
        if (existing.id == asset.id) asset else existing,
    ];
  }
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

/// Holdings sit under the filters on the Wealth tab now rather than on a tab
/// of their own, so reaching one is a scroll rather than a tab change.
///
/// Rows build lazily, so a row above the current position is not in the tree
/// and scrolling further down would never reach it. Each call starts from the
/// top, which makes it independent of where the last one stopped and of the
/// order the box happens to return holdings in.
/// The app opens on Today now, so a test about the Wealth tab has to go there
/// first. Kept as one helper so the landing tab can move again without
/// touching every test that happens to look at holdings.
Future<void> _pumpWealth(WidgetTester tester, {Widget? app}) async {
  await tester.pumpWidget(app ?? _buildApp());
  await _pumpKinetic(tester);
  await tester.tap(find.byKey(const Key('dashboard_nav')));
  await _pumpKinetic(tester);
}

Future<void> _scrollToHolding(WidgetTester tester, Key key) async {
  final scrollable = _verticalScrollableIn(const Key('dashboard_scroll'));
  await tester.drag(scrollable, const Offset(0, 6000));
  await tester.pump();
  await tester.scrollUntilVisible(find.byKey(key), 300, scrollable: scrollable);
}

Future<void> _pumpKinetic(WidgetTester tester) {
  return tester.pump(const Duration(milliseconds: 180));
}

Finder _verticalScrollableIn(Key key) {
  return find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
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