import '../models/metal_price_snapshot.dart';
import '../models/money_entry.dart';
import 'currency_converter.dart';

/// A window of time, inclusive of [start] and exclusive of [end].
class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// Boundaries are built by calendar arithmetic rather than by adding a
  /// `Duration`. A Duration is absolute time, so on the days a clock shifts
  /// for daylight saving, adding 24 hours lands at 23:00 or 01:00 of the wrong
  /// date and an entry falls outside its own day. `DateTime(y, m, d + 1)`
  /// normalises by the calendar and stays on midnight either way.
  factory DateRange.day(DateTime day) {
    return DateRange(
      start: DateTime(day.year, day.month, day.day),
      end: DateTime(day.year, day.month, day.day + 1),
    );
  }

  /// The calendar week containing [day], Monday to Sunday.
  ///
  /// Calendar rather than a rolling seven days: "this week" resetting on a
  /// Monday is what people mean, and a rolling window makes yesterday's total
  /// change every time you look at it.
  factory DateRange.week(DateTime day) {
    final firstDay = day.day - (day.weekday - 1);
    return DateRange(
      start: DateTime(day.year, day.month, firstDay),
      end: DateTime(day.year, day.month, firstDay + 7),
    );
  }

  factory DateRange.month(DateTime day) {
    return DateRange(
      start: DateTime(day.year, day.month),
      end: DateTime(day.year, day.month + 1),
    );
  }

  bool contains(DateTime moment) {
    return !moment.isBefore(start) && moment.isBefore(end);
  }
}

class MoneyTotals {
  const MoneyTotals({
    required this.income,
    required this.expense,
    required this.currency,
    required this.excludedEntryCount,
  });

  final double income;
  final double expense;
  final String currency;

  /// Entries in a currency with no rate. Counted rather than silently dropped,
  /// so the screen can say a total is incomplete instead of quietly lying.
  final int excludedEntryCount;

  double get net => income - expense;
  bool get isComplete => excludedEntryCount == 0;
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.amount,
    required this.direction,
  });

  /// Null for entries saved without one.
  final String? categoryId;
  final double amount;
  final MoneyDirection direction;
}

/// Every figure the wallet shows is summed from entries here. Nothing stores a
/// balance: a stored balance drifts from the entries behind it, and a drifting
/// balance is the problem the wallet exists to remove.
class MoneyLedger {
  const MoneyLedger();

  static List<MoneyEntry> inRange(List<MoneyEntry> entries, DateRange range) {
    return entries
        .where((entry) => range.contains(entry.happenedAt))
        .toList(growable: false);
  }

  /// Newest first, which is the order every screen wants.
  static List<MoneyEntry> newestFirst(List<MoneyEntry> entries) {
    final sorted = [...entries]
      ..sort((a, b) => b.happenedAt.compareTo(a.happenedAt));
    return List.unmodifiable(sorted);
  }

  static MoneyTotals totals(
    List<MoneyEntry> entries, {
    required String displayCurrency,
    MetalPriceSnapshot? prices,
  }) {
    final currency = CurrencyConverter.normalize(displayCurrency);
    var income = 0.0;
    var expense = 0.0;
    var excluded = 0;

    for (final entry in entries) {
      final converted = CurrencyConverter.convert(
        entry.amount,
        from: entry.currency,
        to: currency,
        prices: prices,
      );
      if (converted == null) {
        excluded++;
        continue;
      }
      if (entry.isIncome) {
        income += converted;
      } else {
        expense += converted;
      }
    }

    return MoneyTotals(
      income: income,
      expense: expense,
      currency: currency,
      excludedEntryCount: excluded,
    );
  }

  /// What an account is worth right now, from everything that ever moved
  /// through it. Entries dated in the future are excluded — money promised is
  /// not money held, and zakat cares about the difference.
  static double balanceOf(
    List<MoneyEntry> entries, {
    required String accountId,
    required String currency,
    DateTime? asOf,
    MetalPriceSnapshot? prices,
  }) {
    final cutoff = asOf ?? DateTime.now();
    final target = CurrencyConverter.normalize(currency);
    var balance = 0.0;

    for (final entry in entries) {
      if (entry.accountId != accountId) continue;
      if (entry.happenedAt.isAfter(cutoff)) continue;
      final converted = CurrencyConverter.convert(
        entry.amount,
        from: entry.currency,
        to: target,
        prices: prices,
      );
      if (converted == null) continue;
      balance += converted * entry.direction.sign;
    }
    return balance;
  }

  /// Categories for one direction, the ones used most recently first.
  ///
  /// The category tap is one of the three the capture budget allows, so the
  /// right answer should almost always be near the front. What somebody spent
  /// on an hour ago beats any fixed ordering at predicting that; the seeded
  /// order is only a fallback for categories never used.
  static List<MoneyCategory> byRecentUse(
    List<MoneyCategory> categories,
    List<MoneyEntry> entries, {
    required MoneyDirection direction,
  }) {
    final offered = categories
        .where((category) => !category.isHidden)
        .where((category) => category.direction == direction)
        .toList();

    final lastUsed = <String, DateTime>{};
    for (final entry in entries) {
      if (entry.direction != direction) continue;
      final id = entry.categoryId;
      if (id == null) continue;
      final seen = lastUsed[id];
      if (seen == null || entry.happenedAt.isAfter(seen)) {
        lastUsed[id] = entry.happenedAt;
      }
    }

    offered.sort((a, b) {
      final aUsed = lastUsed[a.id];
      final bUsed = lastUsed[b.id];
      if (aUsed != null && bUsed != null) return bUsed.compareTo(aUsed);
      if (aUsed != null) return -1;
      if (bUsed != null) return 1;
      final byOrder = a.sortIndex.compareTo(b.sortIndex);
      return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
    });
    return List.unmodifiable(offered);
  }

  /// Totals per category for one direction, largest first — the order a
  /// spending breakdown is read in.
  static List<CategoryTotal> byCategory(
    List<MoneyEntry> entries, {
    required MoneyDirection direction,
    required String displayCurrency,
    MetalPriceSnapshot? prices,
  }) {
    final currency = CurrencyConverter.normalize(displayCurrency);
    final sums = <String?, double>{};

    for (final entry in entries) {
      if (entry.direction != direction) continue;
      final converted = CurrencyConverter.convert(
        entry.amount,
        from: entry.currency,
        to: currency,
        prices: prices,
      );
      if (converted == null) continue;
      sums[entry.categoryId] = (sums[entry.categoryId] ?? 0) + converted;
    }

    final totals = sums.entries
        .map(
          (sum) => CategoryTotal(
            categoryId: sum.key,
            amount: sum.value,
            direction: direction,
          ),
        )
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return List.unmodifiable(totals);
  }
}
