import '../services/money_ledger.dart';

/// The windows the Today tab can be read through.
enum SpendingPeriod { today, week, month }

extension SpendingPeriodDetails on SpendingPeriod {
  String get label => switch (this) {
    SpendingPeriod.today => 'Today',
    SpendingPeriod.week => 'Week',
    SpendingPeriod.month => 'Month',
  };

  /// What the big number is called while this window is selected.
  String get spentLabel => switch (this) {
    SpendingPeriod.today => 'Spent today',
    SpendingPeriod.week => 'Spent this week',
    SpendingPeriod.month => 'Spent this month',
  };

  String get emptyLabel => switch (this) {
    SpendingPeriod.today => 'Nothing logged today',
    SpendingPeriod.week => 'Nothing logged this week',
    SpendingPeriod.month => 'Nothing logged this month',
  };

  DateRange rangeAt(DateTime now) => switch (this) {
    SpendingPeriod.today => DateRange.day(now),
    SpendingPeriod.week => DateRange.week(now),
    SpendingPeriod.month => DateRange.month(now),
  };

  /// The window one step wider, used for the comparison line. Today compares
  /// against the week, the week against the month; the month has nothing
  /// wider to sit inside.
  SpendingPeriod? get widerPeriod => switch (this) {
    SpendingPeriod.today => SpendingPeriod.week,
    SpendingPeriod.week => SpendingPeriod.month,
    SpendingPeriod.month => null,
  };
}
