import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/recurring_entry.dart';
import 'package:moniz/providers/recurring_entry_provider.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_recurring_');
    Hive.init(hiveDirectory.path);
    registerMonizAdapters();
    await Hive.openBox<MoneyEntry>('moneyEntries');
    await Hive.openBox<RecurringEntry>('moneyRecurrences');
  });

  setUp(() async {
    await Hive.box<MoneyEntry>('moneyEntries').clear();
    await Hive.box<RecurringEntry>('moneyRecurrences').clear();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  RecurringEntry rent({DateTime? lastRunOn, bool isPaused = false}) {
    return RecurringEntry(
      id: 'rent',
      amount: 1200,
      direction: MoneyDirection.expense,
      frequency: RecurrenceFrequency.monthly,
      dayOfPeriod: 1,
      startsOn: DateTime(2026, 7, 1),
      lastRunOn: lastRunOn,
      isPaused: isPaused,
      categoryId: 'expense.rent',
    );
  }

  test('a rule survives a round trip through the box', () async {
    final notifier = RecurringEntryNotifier(
      ruleBox: Hive.box<RecurringEntry>('moneyRecurrences'),
    );
    await notifier.upsert(rent());

    final reopened = RecurringEntryNotifier(
      ruleBox: Hive.box<RecurringEntry>('moneyRecurrences'),
    );
    final stored = reopened.state.single;
    expect(stored.amount, 1200);
    expect(stored.frequency, RecurrenceFrequency.monthly);
    expect(stored.dayOfPeriod, 1);
    expect(stored.startsOn, DateTime(2026, 7, 1));
    expect(stored.isPaused, isFalse);
    expect(stored.scheduleLabel, 'Every month on the 1st');
  });

  test('startup writes what the rule owes and advances it', () async {
    await Hive.box<RecurringEntry>('moneyRecurrences').put('rent', rent());

    await materialiseDueRecurrences(now: DateTime(2026, 9, 15));

    final entries = Hive.box<MoneyEntry>('moneyEntries').values.toList()
      ..sort((a, b) => a.happenedAt.compareTo(b.happenedAt));
    expect(entries.map((entry) => entry.happenedAt), [
      DateTime(2026, 7, 1),
      DateTime(2026, 8, 1),
      DateTime(2026, 9, 1),
    ]);
    expect(entries.every((entry) => entry.amount == 1200), isTrue);
    expect(
      Hive.box<RecurringEntry>('moneyRecurrences').get('rent')!.lastRunOn,
      DateTime(2026, 9, 1),
    );
  });

  test('a second startup the same day adds nothing', () async {
    await Hive.box<RecurringEntry>('moneyRecurrences').put('rent', rent());
    await materialiseDueRecurrences(now: DateTime(2026, 9, 15));
    final afterFirst = Hive.box<MoneyEntry>('moneyEntries').length;

    await materialiseDueRecurrences(now: DateTime(2026, 9, 15));

    // Reopening the app must not double the rent.
    expect(Hive.box<MoneyEntry>('moneyEntries').length, afterFirst);
  });

  test('a later startup adds only the months that passed', () async {
    await Hive.box<RecurringEntry>('moneyRecurrences').put('rent', rent());
    await materialiseDueRecurrences(now: DateTime(2026, 9, 15));

    await materialiseDueRecurrences(now: DateTime(2026, 11, 3));

    expect(Hive.box<MoneyEntry>('moneyEntries').length, 5);
    expect(
      Hive.box<RecurringEntry>('moneyRecurrences').get('rent')!.lastRunOn,
      DateTime(2026, 11, 1),
    );
  });

  test('a paused rule writes nothing and stays where it was', () async {
    await Hive.box<RecurringEntry>(
      'moneyRecurrences',
    ).put('rent', rent(isPaused: true));

    await materialiseDueRecurrences(now: DateTime(2026, 9, 15));

    expect(Hive.box<MoneyEntry>('moneyEntries'), isEmpty);
    expect(
      Hive.box<RecurringEntry>('moneyRecurrences').get('rent')!.lastRunOn,
      isNull,
    );
  });

  test('an entry generated from a rule can be deleted and stays deleted',
      () async {
    await Hive.box<RecurringEntry>('moneyRecurrences').put('rent', rent());
    await materialiseDueRecurrences(now: DateTime(2026, 9, 15));
    final entries = Hive.box<MoneyEntry>('moneyEntries');
    final first = entries.values.first;

    await entries.delete(first.id);
    await materialiseDueRecurrences(now: DateTime(2026, 9, 15));

    // Regenerating a row somebody deliberately removed would be worse than
    // missing it: they would have to delete it again every launch.
    expect(entries.containsKey(first.id), isFalse);
    expect(entries.length, 2);
  });

  test('pausing and resuming is stored', () async {
    final notifier = RecurringEntryNotifier(
      ruleBox: Hive.box<RecurringEntry>('moneyRecurrences'),
    );
    await notifier.upsert(rent());

    await notifier.setPaused('rent', true);
    expect(notifier.state.single.isPaused, isTrue);

    await notifier.setPaused('rent', false);
    expect(notifier.state.single.isPaused, isFalse);

    await notifier.remove('rent');
    expect(notifier.state, isEmpty);
  });

  test('the recurrence box is encrypted with the rest', () {
    expect(monizBoxNames, contains('moneyRecurrences'));
  });
}
