import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/money_entry.dart';
import 'package:moniz/services/daily_nudge_planner.dart';

const planner = DailyNudgePlanner();
const on = DailyNudgeSettings(isEnabled: true, hour: 20, minute: 30);

MoneyEntry _entry(DateTime when) => MoneyEntry(
  id: when.toIso8601String(),
  amount: 5,
  direction: MoneyDirection.expense,
  happenedAt: when,
);

void main() {
  test('a disabled nudge is never scheduled', () {
    expect(
      planner.nextNudgeAt(
        settings: const DailyNudgeSettings(),
        entries: const [],
        now: DateTime(2026, 9, 7, 9),
      ),
      isNull,
    );
  });

  test('an unlogged day is nudged this evening', () {
    expect(
      planner.nextNudgeAt(
        settings: on,
        entries: const [],
        now: DateTime(2026, 9, 7, 9),
      ),
      DateTime(2026, 9, 7, 20, 30),
    );
  });

  test('a day already logged is skipped to tomorrow', () {
    // Nagging somebody who is keeping up is the fastest way to get
    // notifications turned off for good.
    expect(
      planner.nextNudgeAt(
        settings: on,
        entries: [_entry(DateTime(2026, 9, 7, 8, 15))],
        now: DateTime(2026, 9, 7, 9),
      ),
      DateTime(2026, 9, 8, 20, 30),
    );
  });

  test('a time that has already passed rolls to tomorrow', () {
    expect(
      planner.nextNudgeAt(
        settings: on,
        entries: const [],
        now: DateTime(2026, 9, 7, 21),
      ),
      DateTime(2026, 9, 8, 20, 30),
    );
  });

  test('yesterday being logged does not excuse today', () {
    expect(
      planner.nextNudgeAt(
        settings: on,
        entries: [_entry(DateTime(2026, 9, 6, 19))],
        now: DateTime(2026, 9, 7, 9),
      ),
      DateTime(2026, 9, 7, 20, 30),
    );
  });

  test('rolling to tomorrow crosses a month end', () {
    expect(
      planner.nextNudgeAt(
        settings: on,
        entries: const [],
        now: DateTime(2026, 9, 30, 22),
      ),
      DateTime(2026, 10, 1, 20, 30),
    );
  });

  test('rolling to tomorrow crosses a year end', () {
    expect(
      planner.nextNudgeAt(
        settings: on,
        entries: const [],
        now: DateTime(2026, 12, 31, 23),
      ),
      DateTime(2027, 1, 1, 20, 30),
    );
  });

  test('the chosen time is used, not a fixed one', () {
    expect(
      planner.nextNudgeAt(
        settings: const DailyNudgeSettings(
          isEnabled: true,
          hour: 7,
          minute: 5,
        ),
        entries: const [],
        now: DateTime(2026, 9, 7, 6),
      ),
      DateTime(2026, 9, 7, 7, 5),
    );
  });

  group('time label', () {
    test('reads as a clock, including the awkward hours', () {
      expect(const DailyNudgeSettings(hour: 20, minute: 30).timeLabel, '8:30pm');
      expect(const DailyNudgeSettings(hour: 0, minute: 5).timeLabel, '12:05am');
      expect(const DailyNudgeSettings(hour: 12, minute: 0).timeLabel, '12:00pm');
      expect(const DailyNudgeSettings(hour: 9, minute: 0).timeLabel, '9:00am');
    });
  });
}
