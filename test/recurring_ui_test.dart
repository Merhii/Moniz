import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/recurring_entry.dart';
import 'package:moniz/providers/money_entry_provider.dart';
import 'package:moniz/providers/recurring_entry_provider.dart';
import 'package:moniz/ui/kinetic/kinetic_widgets.dart';
import 'package:moniz/widgets/recurring_entries_screen.dart';

/// Records rule writes instead of persisting them: a Hive write from inside a
/// tap handler never settles under fake async and hangs the run.
class _RecordingEntries extends MoneyEntryNotifier {
  _RecordingEntries({required super.entryBox});

  final added = <MoneyEntry>[];

  @override
  Future<void> addEntry(MoneyEntry entry) async {
    added.add(entry);
    state = [...state, entry];
  }
}

class _RecordingRules extends RecurringEntryNotifier {
  _RecordingRules({required super.ruleBox});

  final saved = <RecurringEntry>[];
  final removed = <String>[];

  @override
  Future<void> upsert(RecurringEntry rule) async {
    saved.add(rule);
    state = [
      for (final existing in state)
        if (existing.id != rule.id) existing,
      rule,
    ];
  }

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    state = [
      for (final existing in state)
        if (existing.id != id) existing,
    ];
  }

  @override
  Future<void> setPaused(String id, bool isPaused) async {
    state = [
      for (final existing in state)
        if (existing.id == id) existing.copyWith(isPaused: isPaused) else existing,
    ];
  }
}

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_recur_ui_');
    Hive.init(hiveDirectory.path);
    registerMonizAdapters();
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
    await seedMoneyDefaults();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  _RecordingRules recorder() =>
      _RecordingRules(ruleBox: Hive.box<RecurringEntry>('moneyRecurrences'));

  Widget app(_RecordingRules rules, {_RecordingEntries? entries}) {
    return ProviderScope(
      overrides: [
        recurringEntryProvider.overrideWith((ref) => rules),
        moneyEntryProvider.overrideWith(
          (ref) =>
              entries ??
              _RecordingEntries(
                entryBox: Hive.box<MoneyEntry>('moneyEntries'),
              ),
        ),
      ],
      child: const MaterialApp(home: RecurringEntriesScreen()),
    );
  }

  Future<void> pump(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 200));

  /// The form is a phone screen's worth of controls. The default 800x600 test
  /// viewport leaves them resting on the bottom edge, where they are in the
  /// tree but the centre a tap aims for is not.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> scrollFormTo(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await pump(tester);
  }

  testWidgets('an empty list explains what a repeat is for', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(app(recorder()));
    await pump(tester);

    expect(find.byKey(const Key('recurring_empty_title')), findsOneWidget);
    expect(find.byKey(const Key('add_recurring_entry')), findsOneWidget);
  });

  testWidgets('a monthly rule is saved and fills in what it already owes', (
    tester,
  ) async {
    final rules = recorder();
    final entries = _RecordingEntries(
      entryBox: Hive.box<MoneyEntry>('moneyEntries'),
    );
    useTallViewport(tester);
    await tester.pumpWidget(app(rules, entries: entries));
    await pump(tester);

    await tester.tap(find.byKey(const Key('add_recurring_entry')));
    await pump(tester);
    await tester.enterText(
      find.byKey(const Key('repeat_amount_field')),
      '1200',
    );
    await tester.tap(find.byKey(const Key('repeat_category_expense.rent')));
    await pump(tester);
    await scrollFormTo(tester, const Key('repeat_save_button'));
    await tester.tap(find.byKey(const Key('repeat_save_button')));
    await pump(tester);

    final rule = rules.saved.first;
    expect(rule.amount, 1200);
    expect(rule.direction, MoneyDirection.expense);
    expect(rule.categoryId, 'expense.rent');
    expect(rule.frequency, RecurrenceFrequency.monthly);
    expect(rule.dayOfPeriod, DateTime.now().day);
    expect(rule.isPaused, isFalse);

    // Starting today, the rule owes today's entry immediately rather than on
    // the next launch. Saving it again records the advanced rule.
    expect(entries.added.single.amount, 1200);
    expect(entries.added.single.categoryId, 'expense.rent');
    expect(rules.saved.last.lastRunOn, isNotNull);
  });

  testWidgets('switching to weekly asks for a weekday, not a month day', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(app(recorder()));
    await pump(tester);
    await tester.tap(find.byKey(const Key('add_recurring_entry')));
    await pump(tester);

    expect(find.byKey(const Key('repeat_month_day')), findsOneWidget);
    expect(find.byKey(const Key('repeat_weekday_1')), findsNothing);

    await scrollFormTo(tester, const Key('repeat_frequency_weekly'));
    await tester.tap(find.byKey(const Key('repeat_frequency_weekly')));
    await pump(tester);

    // A day of the month and a weekday are different numbers, so the picker
    // has to change with the frequency rather than carry a value that would
    // silently mean something else.
    expect(find.byKey(const Key('repeat_month_day')), findsNothing);
    expect(find.byKey(const Key('repeat_weekday_1')), findsOneWidget);
  });

  testWidgets('a rule with a short-month day warns about clamping', (
    tester,
  ) async {
    final rules = recorder();
    useTallViewport(tester);
    await tester.pumpWidget(app(rules));
    await pump(tester);
    await tester.tap(find.byKey(const Key('add_recurring_entry')));
    await pump(tester);

    // The note only appears for days that some months do not have.
    final showsNote = find.byKey(const Key('repeat_clamp_note'));
    expect(showsNote, DateTime.now().day > 28 ? findsOneWidget : findsNothing);
  });

  testWidgets('a saved rule lists its schedule and can be paused', (
    tester,
  ) async {
    final rules = recorder();
    await rules.upsert(
      RecurringEntry(
        id: 'rent',
        amount: 1200,
        direction: MoneyDirection.expense,
        frequency: RecurrenceFrequency.monthly,
        dayOfPeriod: 1,
        startsOn: DateTime(2026, 9, 1),
        categoryId: 'expense.rent',
      ),
    );
    useTallViewport(tester);
    await tester.pumpWidget(app(rules));
    await pump(tester);

    expect(
      tester
          .widget<KineticText>(find.byKey(const Key('recurring_schedule_rent')))
          .text,
      'Every month on the 1st',
    );
    expect(
      tester
          .widget<KineticText>(find.byKey(const Key('recurring_amount_rent')))
          .text,
      '−\$1,200.00',
    );

    await tester.tap(find.byKey(const Key('recurring_pause_rent')));
    await pump(tester);

    expect(
      tester
          .widget<KineticText>(find.byKey(const Key('recurring_schedule_rent')))
          .text,
      'Every month on the 1st · Paused',
    );
  });

  testWidgets('deleting a rule asks first', (tester) async {
    final rules = recorder();
    await rules.upsert(
      RecurringEntry(
        id: 'rent',
        amount: 1200,
        direction: MoneyDirection.expense,
        frequency: RecurrenceFrequency.monthly,
        dayOfPeriod: 1,
        startsOn: DateTime(2026, 9, 1),
        categoryId: 'expense.rent',
      ),
    );
    useTallViewport(tester);
    await tester.pumpWidget(app(rules));
    await pump(tester);

    await tester.tap(find.byKey(const Key('recurring_rule_rent')));
    await pump(tester);
    await pump(tester);
    await scrollFormTo(tester, const Key('repeat_delete_button'));
    await tester.tap(find.byKey(const Key('repeat_delete_button')));
    await pump(tester);
    await pump(tester);
    await tester.tap(find.byKey(const Key('confirm_delete_repeat')));
    await pump(tester);
    await pump(tester);

    expect(rules.removed, ['rent']);
  });

  testWidgets('an amount is required', (tester) async {
    final rules = recorder();
    useTallViewport(tester);
    await tester.pumpWidget(app(rules));
    await pump(tester);
    await tester.tap(find.byKey(const Key('add_recurring_entry')));
    await pump(tester);

    await scrollFormTo(tester, const Key('repeat_save_button'));
    await tester.tap(find.byKey(const Key('repeat_save_button')));
    await pump(tester);

    expect(find.byKey(const Key('repeat_amount_error')), findsOneWidget);
    expect(rules.saved, isEmpty);
  });
}
