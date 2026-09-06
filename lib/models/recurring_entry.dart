import 'package:hive/hive.dart';

import 'money_entry.dart';

part 'recurring_entry.g.dart';

@HiveType(typeId: 13)
enum RecurrenceFrequency {
  @HiveField(0)
  weekly,
  @HiveField(1)
  monthly,
}

extension RecurrenceFrequencyDetails on RecurrenceFrequency {
  String get label =>
      this == RecurrenceFrequency.weekly ? 'Every week' : 'Every month';
}

/// A entry the owner has said will keep happening — salary on the 25th, rent
/// on the 1st. The entries it produces are ordinary [MoneyEntry] records, so
/// every total and the zakat engine treat them like anything else.
@HiveType(typeId: 14)
class RecurringEntry {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final double amount;
  @HiveField(2)
  final MoneyDirection direction;
  @HiveField(3, defaultValue: 'USD')
  final String currency;
  @HiveField(4)
  final String? categoryId;
  @HiveField(5, defaultValue: MoneyAccount.defaultId)
  final String accountId;
  @HiveField(6)
  final String? note;
  @HiveField(7)
  final RecurrenceFrequency frequency;

  /// 1-31 for monthly, 1-7 (Monday-Sunday) for weekly.
  @HiveField(8)
  final int dayOfPeriod;

  /// The first date this can produce an entry for.
  @HiveField(9)
  final DateTime startsOn;

  /// The last date an entry was produced for. Null until it first runs.
  /// Occurrences are generated strictly after this, which is what makes
  /// running the generator twice harmless.
  @HiveField(10)
  final DateTime? lastRunOn;

  @HiveField(11, defaultValue: false)
  final bool isPaused;

  const RecurringEntry({
    required this.id,
    required this.amount,
    required this.direction,
    required this.frequency,
    required this.dayOfPeriod,
    required this.startsOn,
    this.currency = 'USD',
    this.categoryId,
    this.accountId = MoneyAccount.defaultId,
    this.note,
    this.lastRunOn,
    this.isPaused = false,
  });

  RecurringEntry copyWith({
    double? amount,
    MoneyDirection? direction,
    String? currency,
    String? categoryId,
    bool clearCategory = false,
    String? accountId,
    String? note,
    bool clearNote = false,
    RecurrenceFrequency? frequency,
    int? dayOfPeriod,
    DateTime? startsOn,
    DateTime? lastRunOn,
    bool? isPaused,
  }) {
    return RecurringEntry(
      id: id,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      currency: currency ?? this.currency,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      note: clearNote ? null : note ?? this.note,
      frequency: frequency ?? this.frequency,
      dayOfPeriod: dayOfPeriod ?? this.dayOfPeriod,
      startsOn: startsOn ?? this.startsOn,
      lastRunOn: lastRunOn ?? this.lastRunOn,
      isPaused: isPaused ?? this.isPaused,
    );
  }

  /// How the schedule reads in a list.
  String get scheduleLabel {
    if (frequency == RecurrenceFrequency.weekly) {
      const days = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return 'Every ${days[dayOfPeriod - 1]}';
    }
    return 'Every month on the ${_ordinal(dayOfPeriod)}';
  }

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }
}
