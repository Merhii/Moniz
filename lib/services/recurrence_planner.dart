import 'package:uuid/uuid.dart';

import '../models/money_entry.dart';
import '../models/recurring_entry.dart';

/// Works out which occurrences of a recurring entry are owed, and turns them
/// into ordinary entries.
///
/// Pure, and deliberately generates nothing beyond today: a rule for rent on
/// the 1st should not put next month's rent into this month's totals, and
/// zakat is owed on money held rather than money expected.
class RecurrencePlanner {
  const RecurrencePlanner();

  /// A rule left alone for years should not produce thousands of rows on the
  /// next launch. Weekly for a year is 52, so this only bites the pathological
  /// case, and the rule catches up further on each subsequent run.
  static const maxCatchUp = 60;

  List<DateTime> dueDates({required RecurringEntry rule, required DateTime now}) {
    if (rule.isPaused) return const [];

    final today = DateTime(now.year, now.month, now.day);
    final from = rule.lastRunOn == null
        ? _midnight(rule.startsOn)
        : _midnight(rule.lastRunOn!);
    // Strictly after the last run, so running twice in a day produces nothing
    // the second time.
    final exclusive = rule.lastRunOn != null;

    final dates = <DateTime>[];
    for (final date in _occurrences(rule, from, today)) {
      if (date.isAfter(today)) break;
      if (date.isBefore(_midnight(rule.startsOn))) continue;
      if (exclusive && !date.isAfter(from)) continue;
      dates.add(date);
      if (dates.length >= maxCatchUp) break;
    }
    return List.unmodifiable(dates);
  }

  Iterable<DateTime> _occurrences(
    RecurringEntry rule,
    DateTime from,
    DateTime today,
  ) sync* {
    if (rule.frequency == RecurrenceFrequency.weekly) {
      // Step to the first matching weekday on or after `from`.
      final offset = (rule.dayOfPeriod - from.weekday + 7) % 7;
      var date = DateTime(from.year, from.month, from.day + offset);
      while (!date.isAfter(today)) {
        yield date;
        date = DateTime(date.year, date.month, date.day + 7);
      }
      return;
    }

    var year = from.year;
    var month = from.month;
    while (true) {
      final date = _monthlyDate(year, month, rule.dayOfPeriod);
      if (date.isAfter(today)) return;
      if (!date.isBefore(from) ||
          (date.year == from.year && date.month == from.month)) {
        yield date;
      }
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
  }

  /// The 31st does not exist in February. Clamping to the month's last day is
  /// what "the 31st" has to mean, otherwise the rule silently skips the short
  /// months — which for rent or salary is the wrong answer every time.
  static DateTime _monthlyDate(int year, int month, int dayOfMonth) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, dayOfMonth > lastDay ? lastDay : dayOfMonth);
  }

  static DateTime _midnight(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// The entries [rule] owes, and the rule advanced past them.
  ({List<MoneyEntry> entries, RecurringEntry rule}) materialise({
    required RecurringEntry rule,
    required DateTime now,
    String Function()? idFactory,
  }) {
    final dates = dueDates(rule: rule, now: now);
    if (dates.isEmpty) return (entries: const <MoneyEntry>[], rule: rule);

    final newId = idFactory ?? () => const Uuid().v4();
    final entries = [
      for (final date in dates)
        MoneyEntry(
          id: newId(),
          amount: rule.amount,
          direction: rule.direction,
          currency: rule.currency,
          happenedAt: date,
          accountId: rule.accountId,
          categoryId: rule.categoryId,
          note: rule.note,
        ),
    ];
    return (entries: entries, rule: rule.copyWith(lastRunOn: dates.last));
  }
}
