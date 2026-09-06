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
import 'package:moniz/providers/app_lock_provider.dart';
import 'package:moniz/providers/metal_price_provider.dart';
import 'package:moniz/providers/money_entry_provider.dart';
import 'package:moniz/services/app_lock_service.dart';
import 'package:moniz/services/biometric_auth_service.dart';
import 'package:moniz/services/metal_price_service.dart';
import 'package:moniz/services/money_ledger.dart';
import 'package:moniz/ui/kinetic/kinetic_widgets.dart';

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
    await Hive.openBox<RecurringEntry>('moneyRecurrences');
  });

  setUp(() async {
    await Hive.box<MoneyEntry>('moneyEntries').clear();
    await Hive.box<MoneyCategory>('moneyCategories').clear();
    await Hive.box<MoneyAccount>('moneyAccounts').clear();
    await Hive.box<RecurringEntry>('moneyRecurrences').clear();
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
    expect(find.byKey(const Key('breakdown_expense.groceries')), findsOneWidget);
    // The row, and the "Left" figure, which is −12 with nothing coming in.
    // The id is generated, so the row is reached by predicate rather than key.
    await tester.scrollUntilVisible(
      find.byWidgetPredicate(
        (widget) =>
            widget is KineticText &&
            widget.key.toString().contains('money_entry_amount_'),
      ),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('today_scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final entryAmount = find.byWidgetPredicate(
      (widget) =>
          widget is KineticText &&
          widget.key.toString().contains('money_entry_amount_'),
    );
    expect(tester.widget<KineticText>(entryAmount).text, '−\$12.00');
    expect(
      tester.widget<KineticText>(find.byKey(const Key('flow_expense'))).text,
      '\$12.00',
    );
    expect(
      tester.widget<KineticText>(find.byKey(const Key('flow_net'))).text,
      '−\$12.00',
    );
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

  testWidgets('switching direction leaves you in the amount field', (
    tester,
  ) async {
    final entries = _recorder();
    await tester.pumpWidget(_buildApp(entries: entries));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add_money_entry')));
    await _pump(tester);

    Future<bool> amountHasFocus() async => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('money_amount_field')),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;

    expect(await amountHasFocus(), isTrue, reason: 'autofocus on open');

    // On a device, tapping any control outside the field fires its
    // onTapOutside and drops focus — that is what made a switch-then-type
    // income entry silently save nothing. A synthetic tap does not reproduce
    // it, so the drop is done explicitly here and the toggle has to put focus
    // back. Without that, this expectation fails.
    FocusManager.instance.primaryFocus?.unfocus();
    await _pump(tester);
    expect(await amountHasFocus(), isFalse, reason: 'focus really was lost');

    await tester.tap(find.byKey(const Key('money_direction_income')));
    await _pump(tester);
    expect(await amountHasFocus(), isTrue);

    // And typing lands, rather than going nowhere.
    await tester.enterText(find.byKey(const Key('money_amount_field')), '2500');
    await tester.tap(find.byKey(const Key('money_category_income.salary')));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);

    expect(entries.added.single.amount, 2500);
    expect(entries.added.single.direction, MoneyDirection.income);
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

    await _scrollTodayTo(tester, const Key('money_entry_lunch'));
    await tester.tap(find.byKey(const Key('money_entry_lunch')));
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('money_amount_field')), '15');
    await tester.tap(find.byKey(const Key('money_save_button')));
    await _pump(tester);

    expect(entries.added, isEmpty, reason: 'edited, not added');
    expect(entries.updated.single.id, 'lunch');
    expect(entries.updated.single.amount, 15);
  });

  testWidgets('the period switch changes the window, not just the label', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.runAsync(() async {
      final box = Hive.box<MoneyEntry>('moneyEntries');
      await box.put(
        'today',
        MoneyEntry(
          id: 'today',
          amount: 10,
          direction: MoneyDirection.expense,
          happenedAt: now,
          categoryId: 'expense.groceries',
        ),
      );
      // Far enough back to be outside today and this week, but inside a month
      // for most of any month. Placed on the 1st so the month always holds it.
      await box.put(
        'earlier',
        MoneyEntry(
          id: 'earlier',
          amount: 100,
          direction: MoneyDirection.expense,
          happenedAt: DateTime(now.year, now.month, 1, 9),
          categoryId: 'expense.rent',
        ),
      );
    });

    await tester.pumpWidget(_buildApp());
    await _pump(tester);

    expect(
      tester.widget<KineticText>(find.byKey(const Key('today_spend_label'))).text,
      'Spent today',
    );

    await tester.tap(find.byKey(const Key('spending_period_month')));
    await _pump(tester);

    expect(
      tester.widget<KineticText>(find.byKey(const Key('today_spend_label'))).text,
      'Spent this month',
    );
    // The month total has to actually include the older entry, not just
    // rename the heading above the same number.
    expect(
      tester.widget<KineticText>(find.byKey(const Key('flow_expense'))).text,
      '\$110.00',
    );
    expect(find.byKey(const Key('breakdown_expense.rent')), findsOneWidget);
  });

  testWidgets('the widest window has nothing wider to compare against', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<MoneyEntry>('moneyEntries').put(
        'today',
        MoneyEntry(
          id: 'today',
          amount: 10,
          direction: MoneyDirection.expense,
          happenedAt: DateTime.now(),
        ),
      );
    });
    await tester.pumpWidget(_buildApp());
    await _pump(tester);

    expect(find.byKey(const Key('today_wider_total')), findsOneWidget);

    await tester.tap(find.byKey(const Key('spending_period_month')));
    await _pump(tester);

    expect(find.byKey(const Key('today_wider_total')), findsNothing);
  });

  testWidgets('adding offers no delete, because there is nothing to delete', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add_money_entry')));
    await _pump(tester);
    await _scrollCapture(tester);

    expect(find.byKey(const Key('money_save_button')), findsOneWidget);
    expect(find.byKey(const Key('money_delete_button')), findsNothing);
  });

  testWidgets('cancelling the delete confirmation keeps the entry', (
    tester,
  ) async {
    final entries = await _openEntryForEditing(tester);
    await _tapDelete(tester);

    await tester.tap(find.byKey(const Key('cancel_delete_entry')));
    await _pump(tester);
    await _pump(tester);

    expect(find.byKey(const Key('cancel_delete_entry')), findsNothing);
    expect(entries.removed, isEmpty);
  });

  testWidgets('confirming the delete removes the entry', (tester) async {
    final entries = await _openEntryForEditing(tester);
    await _tapDelete(tester);

    await tester.tap(find.byKey(const Key('confirm_delete_entry')));
    await _pump(tester);
    await _pump(tester);

    expect(entries.removed, ['lunch']);
    expect(entries.updated, isEmpty, reason: 'deleted, not saved');
    expect(find.byKey(const Key('money_entry_lunch')), findsNothing);
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
  final removed = <String>[];

  @override
  Future<void> addEntry(MoneyEntry entry) async {
    added.add(entry);
    state = [...state, entry];
  }

  @override
  Future<void> removeEntry(String id) async {
    removed.add(id);
    state = [
      for (final existing in state)
        if (existing.id != id) existing,
    ];
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

/// Today gained a row above the entries, so a row can start below the test
/// viewport. The list builds lazily, so it has to be scrolled to rather than
/// made visible.
Future<void> _scrollTodayTo(WidgetTester tester, Key key) {
  return tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('today_scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

/// The capture sheet is taller than a test viewport and its list builds
/// lazily, so a control at the foot is not in the tree until scrolled to.
/// `ensureVisible` cannot reach an element that does not exist yet.
Future<void> _scrollCaptureTo(WidgetTester tester, Key key) {
  return tester.scrollUntilVisible(
    find.byKey(key),
    200,
    // The text fields carry their own Scrollables, so take the list's own —
    // the outermost, and therefore first in a depth-first walk.
    scrollable: find
        .descendant(
          of: find.byKey(const Key('money_capture_scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

/// Seeds one entry, opens it for editing, and hands back the recorder.
Future<_RecordingEntries> _openEntryForEditing(WidgetTester tester) async {
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
  await _scrollTodayTo(tester, const Key('money_entry_lunch'));
  await tester.tap(find.byKey(const Key('money_entry_lunch')));
  await _pump(tester);
  await _pump(tester);
  return entries;
}

/// Brings the delete button into the tree, taps it, and lets the confirmation
/// build. Both the cancel and the confirm path start here, and the sheet's
/// scroll position is not assumed between them.
Future<void> _tapDelete(WidgetTester tester) async {
  await _scrollCaptureTo(tester, const Key('money_delete_button'));
  await tester.tap(find.byKey(const Key('money_delete_button')));
  await _pump(tester);
  await _pump(tester);
}

/// Scrolls the sheet to its foot without needing a target.
Future<void> _scrollCapture(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('money_capture_scroll')),
    const Offset(0, -400),
  );
  await tester.pump();
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
