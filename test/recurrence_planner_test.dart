import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/recurring_entry.dart';
import 'package:moniz/services/recurrence_planner.dart';

const planner = RecurrencePlanner();

RecurringEntry _monthly({
  required int day,
  required DateTime startsOn,
  DateTime? lastRunOn,
  bool isPaused = false,
}) {
  return RecurringEntry(
    id: 'rent',
    amount: 1200,
    direction: MoneyDirection.expense,
    frequency: RecurrenceFrequency.monthly,
    dayOfPeriod: day,
    startsOn: startsOn,
    lastRunOn: lastRunOn,
    isPaused: isPaused,
    categoryId: 'expense.rent',
  );
}

RecurringEntry _weekly({
  required int weekday,
  required DateTime startsOn,
  DateTime? lastRunOn,
}) {
  return RecurringEntry(
    id: 'wage',
    amount: 200,
    direction: MoneyDirection.income,
    frequency: RecurrenceFrequency.weekly,
    dayOfPeriod: weekday,
    startsOn: startsOn,
    lastRunOn: lastRunOn,
  );
}

void main() {
  group('monthly', () {
    test('produces every month up to today and no further', () {
      final dates = planner.dueDates(
        rule: _monthly(day: 1, startsOn: DateTime(2026, 7, 1)),
        now: DateTime(2026, 9, 15),
      );

      // Not October: rent that has not happened must not sit in a total.
      expect(dates, [
        DateTime(2026, 7, 1),
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      ]);
    });

    test('the 31st clamps to the last day of a shorter month', () {
      final dates = planner.dueDates(
        rule: _monthly(day: 31, startsOn: DateTime(2026, 1, 31)),
        now: DateTime(2026, 4, 30),
      );

      // Skipping February entirely would drop a month of rent.
      expect(dates, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('February clamps to 29 in a leap year', () {
      final dates = planner.dueDates(
        rule: _monthly(day: 30, startsOn: DateTime(2028, 2, 1)),
        now: DateTime(2028, 2, 29),
      );

      expect(dates, [DateTime(2028, 2, 29)]);
    });

    test('a due date today is produced, not held back', () {
      final dates = planner.dueDates(
        rule: _monthly(day: 9, startsOn: DateTime(2026, 9, 1)),
        now: DateTime(2026, 9, 9, 8),
      );

      expect(dates, [DateTime(2026, 9, 9)]);
    });

    test('nothing is owed before the rule starts', () {
      final dates = planner.dueDates(
        rule: _monthly(day: 1, startsOn: DateTime(2026, 9, 1)),
        now: DateTime(2026, 8, 15),
      );

      expect(dates, isEmpty);
    });
  });

  group('running twice', () {
    test('a second run the same day produces nothing', () {
      final rule = _monthly(day: 1, startsOn: DateTime(2026, 7, 1));
      final first = planner.materialise(
        rule: rule,
        now: DateTime(2026, 9, 15),
        idFactory: _ids(),
      );
      expect(first.entries, hasLength(3));

      final second = planner.materialise(
        rule: first.rule,
        now: DateTime(2026, 9, 15),
        idFactory: _ids(),
      );
      // Opening the app twice must not double the rent.
      expect(second.entries, isEmpty);
      expect(second.rule.lastRunOn, DateTime(2026, 9, 1));
    });

    test('a later run picks up only what came after', () {
      final rule = _monthly(
        day: 1,
        startsOn: DateTime(2026, 7, 1),
        lastRunOn: DateTime(2026, 8, 1),
      );

      expect(planner.dueDates(rule: rule, now: DateTime(2026, 10, 5)), [
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 1),
      ]);
    });
  });

  group('weekly', () {
    test('lands on the chosen weekday every week', () {
      // 7 Sep 2026 is a Monday.
      final dates = planner.dueDates(
        rule: _weekly(weekday: DateTime.friday, startsOn: DateTime(2026, 9, 7)),
        now: DateTime(2026, 9, 26),
      );

      expect(dates, [
        DateTime(2026, 9, 11),
        DateTime(2026, 9, 18),
        DateTime(2026, 9, 25),
      ]);
      expect(dates.every((date) => date.weekday == DateTime.friday), isTrue);
    });

    test('a start date already on the weekday counts that day', () {
      final dates = planner.dueDates(
        rule: _weekly(weekday: DateTime.monday, startsOn: DateTime(2026, 9, 7)),
        now: DateTime(2026, 9, 7),
      );

      expect(dates, [DateTime(2026, 9, 7)]);
    });
  });

  group('pausing and catching up', () {
    test('a paused rule owes nothing', () {
      final dates = planner.dueDates(
        rule: _monthly(
          day: 1,
          startsOn: DateTime(2026, 1, 1),
          isPaused: true,
        ),
        now: DateTime(2026, 9, 15),
      );

      expect(dates, isEmpty);
    });

    test('a long absence is capped rather than flooding the ledger', () {
      final dates = planner.dueDates(
        rule: _weekly(weekday: DateTime.monday, startsOn: DateTime(2020, 1, 6)),
        now: DateTime(2026, 9, 15),
      );

      expect(dates, hasLength(RecurrencePlanner.maxCatchUp));
    });
  });

  group('materialising', () {
    test('produces ordinary entries carrying the rule details', () {
      final result = planner.materialise(
        rule: _monthly(day: 1, startsOn: DateTime(2026, 9, 1)),
        now: DateTime(2026, 9, 15),
        idFactory: _ids(),
      );

      final entry = result.entries.single;
      expect(entry.amount, 1200);
      expect(entry.direction, MoneyDirection.expense);
      expect(entry.categoryId, 'expense.rent');
      expect(entry.happenedAt, DateTime(2026, 9, 1));
      expect(entry.accountId, MoneyAccount.defaultId);
      // Dated when it happened, not when the app noticed.
      expect(entry.happenedAt.day, 1);
    });

    test('the rule advances to the last date it produced', () {
      final result = planner.materialise(
        rule: _monthly(day: 1, startsOn: DateTime(2026, 7, 1)),
        now: DateTime(2026, 9, 15),
        idFactory: _ids(),
      );

      expect(result.rule.lastRunOn, DateTime(2026, 9, 1));
    });
  });
}

String Function() _ids() {
  var next = 0;
  return () => 'generated-${next++}';
}
