import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/money_entry.dart';
import 'package:moniz/services/money_ledger.dart';
import 'package:moniz/widgets/spending_period.dart';

void main() {
  group('week', () {
    test('runs Monday to Sunday around any day in it', () {
      // 9 Sep 2026 is a Wednesday.
      final week = DateRange.week(DateTime(2026, 9, 9, 15));

      expect(week.start, DateTime(2026, 9, 7));
      expect(week.end, DateTime(2026, 9, 14));
      expect(week.contains(DateTime(2026, 9, 7)), isTrue);
      expect(week.contains(DateTime(2026, 9, 13, 23, 59)), isTrue);
      expect(week.contains(DateTime(2026, 9, 14)), isFalse);
      expect(week.contains(DateTime(2026, 9, 6, 23, 59)), isFalse);
    });

    test('a Monday belongs to the week it starts', () {
      final week = DateRange.week(DateTime(2026, 9, 7));
      expect(week.start, DateTime(2026, 9, 7));
    });

    test('a Sunday belongs to the week it ends, not the next one', () {
      // The off-by-one that ISO weekday numbering invites.
      final week = DateRange.week(DateTime(2026, 9, 13, 20));
      expect(week.start, DateTime(2026, 9, 7));
      expect(week.end, DateTime(2026, 9, 14));
    });

    test('a week spanning a month boundary still runs seven days', () {
      // 1 Oct 2026 is a Thursday, so its week starts in September.
      final week = DateRange.week(DateTime(2026, 10, 1));
      expect(week.start, DateTime(2026, 9, 28));
      expect(week.end, DateTime(2026, 10, 5));
      expect(week.end.difference(week.start).inDays, 7);
    });

    test('a week spanning a year boundary still runs seven days', () {
      final week = DateRange.week(DateTime(2027, 1, 1));
      expect(week.start, DateTime(2026, 12, 28));
      expect(week.end, DateTime(2027, 1, 4));
    });
  });

  group('day boundaries survive calendar arithmetic', () {
    test('a day is midnight to midnight', () {
      final day = DateRange.day(DateTime(2026, 3, 29, 14));
      expect(day.start, DateTime(2026, 3, 29));
      expect(day.end, DateTime(2026, 3, 30));
    });

    test('the last day of a month rolls into the next', () {
      final day = DateRange.day(DateTime(2026, 1, 31, 9));
      expect(day.end, DateTime(2026, 2, 1));
    });

    test('the last day of a year rolls into the next', () {
      final day = DateRange.day(DateTime(2026, 12, 31, 9));
      expect(day.end, DateTime(2027, 1, 1));
    });
  });

  group('periods', () {
    final now = DateTime(2026, 9, 9, 12);

    test('each period asks for its own window', () {
      expect(SpendingPeriod.today.rangeAt(now).start, DateTime(2026, 9, 9));
      expect(SpendingPeriod.week.rangeAt(now).start, DateTime(2026, 9, 7));
      expect(SpendingPeriod.month.rangeAt(now).start, DateTime(2026, 9));
    });

    test('each sits inside the next, and the month sits inside nothing', () {
      expect(SpendingPeriod.today.widerPeriod, SpendingPeriod.week);
      expect(SpendingPeriod.week.widerPeriod, SpendingPeriod.month);
      expect(SpendingPeriod.month.widerPeriod, isNull);
    });
  });

  test('a wider window includes what a narrower one does', () {
    final now = DateTime(2026, 9, 9, 12);
    final entries = [
      for (var day = 6; day <= 12; day++)
        MoneyEntry(
          id: 'd$day',
          amount: 10,
          direction: MoneyDirection.expense,
          happenedAt: DateTime(2026, 9, day, 10),
        ),
    ];

    final today = MoneyLedger.inRange(
      entries,
      SpendingPeriod.today.rangeAt(now),
    );
    final week = MoneyLedger.inRange(entries, SpendingPeriod.week.rangeAt(now));
    final month = MoneyLedger.inRange(
      entries,
      SpendingPeriod.month.rangeAt(now),
    );

    expect(today.map((e) => e.id), ['d9']);
    // 6 Sep is the Sunday before, so it falls outside the week but inside the
    // month — exactly the case a rolling seven-day window would get wrong.
    expect(week.map((e) => e.id), ['d7', 'd8', 'd9', 'd10', 'd11', 'd12']);
    expect(month, hasLength(7));
  });
}
