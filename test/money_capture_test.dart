import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/portfolio_snapshot.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/providers/app_lock_provider.dart';
import 'package:moniz/providers/metal_price_provider.dart';
import 'package:moniz/providers/money_entry_provider.dart';
import 'package:moniz/services/app_lock_service.dart';
import 'package:moniz/services/biometric_auth_service.dart';
import 'package:moniz/services/metal_price_service.dart';
import 'package:moniz/services/money_ledger.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_capture_');
    Hive.init(hiveDirectory.path);
    registerMonizAdapters();
    await Hive.openBox<Asset>('assets');
    await Hive.openBox<MetalPriceSnapshot>('metalPrices');
    await Hive.openBox<ZakatSettings>('zakatSettings');
    await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
    await Hive.openBox<PortfolioSnapshot>('portfolioSnapshots');
    await Hive.openBox<dynamic>('uiPreferences');
    await Hive.openBox<MoneyEntry>('moneyEntries');
    await Hive.openBox<MoneyCategory>('moneyCategories');
    await Hive.openBox<MoneyAccount>('moneyAccounts');
  });

  setUp(() async {
    await Hive.box<MoneyEntry>('moneyEntries').clear();
    await Hive.box<MoneyCategory>('moneyCategories').clear();
    await Hive.box<MoneyAccount>('moneyAccounts').clear();
    await Hive.box<dynamic>('uiPreferences').clear();
    await seedMoneyDefaults();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  testWidgets('the app opens on Today', (tester) async {
    await tester.pumpWidget(_buildApp());
    await _pump(tester);

    // A wallet that opens on a total-wealth screen is telling you it is not
    // really a wallet.
    expect(find.byKey(const Key('today_spend_total')), findsOneWidget);
    expect(find.byKey(const Key('today_empty_title')), findsOneWidget);
  });

  testWidgets('an expense takes an amount, a category and save', (
    tester,
  ) async {
    final entries = _recorder();
    await tester.pumpWidget(_buildApp(entries: entries));
    await _pump(tester);

    // Tap 1: open capture.
    await tester.tap(find.byKey(const Key('add_money_entry')));
    await _pump(tester);

    // No tap to reach the amount: the field opens focused, which is what
    // keeps this to three taps rather than four.
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('money_amount_field')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );

    // Typed, not tapped.
    await tester.enterText(
      find.byKey(const Key('money_amount_field')),
      '3.50',
    );
    // Tap 2: a category.
    await tester.tap(find.byKey(const Key('money_category_expense.eatingout')));
    await _pump(tester);
    // Tap 3: save. Date, currency and account were already right.
    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);

    final entry = entries.added.single;
    expect(entry.amount, 3.5);
    expect(entry.direction, MoneyDirection.expense);
    expect(entry.categoryId, 'expense.eatingout');
    expect(entry.currency, 'USD');
    expect(entry.accountId, MoneyAccount.defaultId);
    expect(
      DateTime.now().difference(entry.happenedAt).inMinutes.abs(),
      lessThan(2),
      reason: 'defaults to now',
    );
  });

  testWidgets('the entry shows up on Today and moves the total', (
    tester,
  ) async {
    final entries = _recorder();
    await tester.pumpWidget(_buildApp(entries: entries));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add_money_entry')));
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('money_amount_field')), '12');
    await tester.tap(find.byKey(const Key('money_category_expense.groceries')));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);

    expect(find.byKey(const Key('today_empty_title')), findsNothing);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('−\$12.00'), findsOneWidget);
  });

  testWidgets('income is a different direction, not a negative amount', (
    tester,
  ) async {
    final entries = _recorder();
    await tester.pumpWidget(_buildApp(entries: entries));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add_money_entry')));
    await _pump(tester);

    await tester.tap(find.byKey(const Key('money_direction_income')));
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('money_amount_field')), '3000');
    await tester.tap(find.byKey(const Key('money_category_income.salary')));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);

    final entry = entries.added.single;
    expect(entry.amount, 3000, reason: 'stored positive');
    expect(entry.direction, MoneyDirection.income);
    expect(entry.signedAmount, 3000);
  });

  testWidgets('switching direction drops a category that no longer applies', (
    tester,
  ) async {
    final entries = _recorder();
    await tester.pumpWidget(_buildApp(entries: entries));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add_money_entry')));
    await _pump(tester);

    await tester.tap(find.byKey(const Key('money_category_expense.groceries')));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('money_direction_income')));
    await _pump(tester);

    // Groceries is not an income category, so it must not survive the switch
    // and be saved against an income entry.
    expect(
      find.byKey(const Key('money_category_expense.groceries')),
      findsNothing,
    );
    await tester.enterText(find.byKey(const Key('money_amount_field')), '50');
    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);

    expect(entries.added.single.categoryId, isNull);
  });

  testWidgets('a missing or zero amount is refused, not saved as nothing', (
    tester,
  ) async {
    final entries = _recorder();
    await tester.pumpWidget(_buildApp(entries: entries));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add_money_entry')));
    await _pump(tester);

    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);
    expect(find.byKey(const Key('money_amount_error')), findsOneWidget);
    expect(entries.added, isEmpty);

    await tester.enterText(find.byKey(const Key('money_amount_field')), '0');
    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);
    expect(find.text('Amount must be more than zero'), findsOneWidget);
    expect(entries.added, isEmpty);
  });

  testWidgets('date, currency and note stay behind a disclosure', (
    tester,
  ) async {
    final entries = _recorder();
    await tester.pumpWidget(_buildApp(entries: entries));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add_money_entry')));
    await _pump(tester);

    // None of these are on the fast path.
    expect(find.byKey(const Key('money_date_field')), findsNothing);
    expect(find.byKey(const Key('money_note_field')), findsNothing);
    expect(find.byKey(const Key('money_currency_EUR')), findsNothing);

    await tester.tap(find.byKey(const Key('money_capture_more')));
    await _pump(tester);

    expect(find.byKey(const Key('money_date_field')), findsOneWidget);
    expect(find.byKey(const Key('money_note_field')), findsOneWidget);
    expect(find.byKey(const Key('money_currency_EUR')), findsOneWidget);
  });

  testWidgets('tapping an entry edits it rather than adding another', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<MoneyEntry>('moneyEntries').put(
        'lunch',
        MoneyEntry(
          id: 'lunch',
          amount: 12,
          direction: MoneyDirection.expense,
          happenedAt: DateTime.now(),
          categoryId: 'expense.eatingout',
        ),
      );
    });
    final entries = _recorder();
    await tester.pumpWidget(_buildApp(entries: entries));
    await _pump(tester);

    await tester.tap(find.byKey(const Key('money_entry_lunch')));
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('money_amount_field')), '15');
    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);

    expect(entries.added, isEmpty, reason: 'edited, not added');
    expect(entries.updated.single.id, 'lunch');
    expect(entries.updated.single.amount, 15);
  });

  group('category ordering', () {
    final categories = [
      const MoneyCategory(
        id: 'a',
        label: 'A',
        direction: MoneyDirection.expense,
        sortIndex: 0,
      ),
      const MoneyCategory(
        id: 'b',
        label: 'B',
        direction: MoneyDirection.expense,
        sortIndex: 1,
      ),
      const MoneyCategory(
        id: 'hidden',
        label: 'Hidden',
        direction: MoneyDirection.expense,
        sortIndex: 2,
        isHidden: true,
      ),
      const MoneyCategory(
        id: 'income',
        label: 'Salary',
        direction: MoneyDirection.income,
      ),
    ];

    MoneyEntry used(String categoryId, DateTime when) => MoneyEntry(
      id: categoryId + when.toIso8601String(),
      amount: 1,
      direction: MoneyDirection.expense,
      happenedAt: when,
      categoryId: categoryId,
    );

    test('the most recently used comes first', () {
      final ordered = MoneyLedger.byRecentUse(
        categories,
        [used('b', DateTime(2026, 9, 6))],
        direction: MoneyDirection.expense,
      );

      // 'b' sorts after 'a' by seeded order, but it was just used.
      expect(ordered.map((c) => c.id), ['b', 'a']);
    });

    test('unused ones keep the seeded order behind the used ones', () {
      final ordered = MoneyLedger.byRecentUse(
        categories,
        [used('b', DateTime(2026, 9, 1)), used('a', DateTime(2026, 9, 6))],
        direction: MoneyDirection.expense,
      );

      expect(ordered.map((c) => c.id), ['a', 'b']);
    });

    test('hidden categories and the other direction are not offered', () {
      final ordered = MoneyLedger.byRecentUse(
        categories,
        const [],
        direction: MoneyDirection.expense,
      );

      expect(ordered.map((c) => c.id), ['a', 'b']);
    });
  });
}

/// Records writes instead of persisting them. A Hive write issued from inside
/// a tap handler never settles under fake async and hangs the whole run, which
/// is what the rest of this suite works around the same way.
class _RecordingEntries extends MoneyEntryNotifier {
  _RecordingEntries({required super.entryBox});

  final added = <MoneyEntry>[];
  final updated = <MoneyEntry>[];

  @override
  Future<void> addEntry(MoneyEntry entry) async {
    added.add(entry);
    state = [...state, entry];
  }

  @override
  Future<void> updateEntry(MoneyEntry entry) async {
    updated.add(entry);
    state = [
      for (final existing in state)
        if (existing.id == entry.id) entry else existing,
    ];
  }
}

_RecordingEntries _recorder() =>
    _RecordingEntries(entryBox: Hive.box<MoneyEntry>('moneyEntries'));

Future<void> _pump(WidgetTester tester) {
  return tester.pump(const Duration(milliseconds: 200));
}

Widget _buildApp({_RecordingEntries? entries}) {
  return ProviderScope(
    overrides: [
      if (entries != null) moneyEntryProvider.overrideWith((ref) => entries),
      appLockStorageProvider.overrideWithValue(_InMemoryAppLockStorage()),
      biometricAuthServiceProvider.overrideWithValue(
        const _UnavailableBiometrics(),
      ),
      metalPriceServiceProvider.overrideWithValue(_UnavailablePrices()),
      metalPriceHistoryServiceProvider.overrideWithValue(
        const _UnavailableHistory(),
      ),
    ],
    child: const MonizApp(),
  );
}

class _UnavailablePrices implements MetalPriceService {
  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    throw const MetalPriceException('Unavailable in widget test.');
  }
}

class _UnavailableBiometrics implements BiometricAuthService {
  const _UnavailableBiometrics();

  @override
  Future<bool> authenticate() async => false;

  @override
  Future<AppBiometricType> availableType() async => AppBiometricType.none;
}

class _UnavailableHistory implements MetalPriceHistoryService {
  const _UnavailableHistory();

  @override
  Future<List<MetalPriceSnapshot>> fetchWeeklyAverages({
    required int days,
  }) async {
    throw const MetalPriceException('Unavailable in widget test.');
  }
}

class _InMemoryAppLockStorage implements AppLockStorage {
  final _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
