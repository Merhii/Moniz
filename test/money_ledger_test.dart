import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/money_entry.dart';
import 'package:moniz/services/money_ledger.dart';

MoneyEntry _entry({
  String id = 'e',
  double amount = 10,
  MoneyDirection direction = MoneyDirection.expense,
  String currency = 'USD',
  DateTime? happenedAt,
  String accountId = MoneyAccount.defaultId,
  String? categoryId,
}) {
  return MoneyEntry(
    id: id,
    amount: amount,
    direction: direction,
    currency: currency,
    happenedAt: happenedAt ?? DateTime(2026, 9, 6, 12),
    accountId: accountId,
    categoryId: categoryId,
  );
}

void main() {
  group('amounts and signs', () {
    test('amount stays positive and direction carries the sign', () {
      expect(_entry(amount: 10).signedAmount, -10);
      expect(
        _entry(amount: 10, direction: MoneyDirection.income).signedAmount,
        10,
      );
    });
  });

  group('totals', () {
    test('income and expense are kept apart, and net is the difference', () {
      final totals = MoneyLedger.totals(
        [
          _entry(id: 'a', amount: 3000, direction: MoneyDirection.income),
          _entry(id: 'b', amount: 900),
          _entry(id: 'c', amount: 100),
        ],
        displayCurrency: 'USD',
      );

      expect(totals.income, 3000);
      expect(totals.expense, 1000);
      expect(totals.net, 2000);
      expect(totals.isComplete, isTrue);
    });

    test('a currency with no rate is counted out loud, not dropped', () {
      final totals = MoneyLedger.totals(
        [_entry(id: 'a', amount: 50), _entry(id: 'b', amount: 20, currency: 'JPY')],
        displayCurrency: 'USD',
      );

      // Silently ignoring it would show a total that looks complete and is not.
      expect(totals.expense, 50);
      expect(totals.excludedEntryCount, 1);
      expect(totals.isComplete, isFalse);
    });

    test('totals convert into the display currency', () {
      final totals = MoneyLedger.totals(
        [_entry(amount: 100)],
        displayCurrency: 'AED',
      );

      expect(totals.expense, closeTo(367.25, 0.01));
      expect(totals.currency, 'AED');
    });
  });

  group('balance', () {
    test('is summed from entries, income up and expense down', () {
      final balance = MoneyLedger.balanceOf(
        [
          _entry(id: 'a', amount: 3000, direction: MoneyDirection.income),
          _entry(id: 'b', amount: 1200),
        ],
        accountId: MoneyAccount.defaultId,
        currency: 'USD',
        asOf: DateTime(2026, 9, 7),
      );

      expect(balance, 1800);
    });

    test('another account does not move this one', () {
      final balance = MoneyLedger.balanceOf(
        [
          _entry(id: 'a', amount: 500, direction: MoneyDirection.income),
          _entry(id: 'b', amount: 400, accountId: 'savings'),
        ],
        accountId: MoneyAccount.defaultId,
        currency: 'USD',
        asOf: DateTime(2026, 9, 7),
      );

      expect(balance, 500);
    });

    test('money dated in the future is not money held yet', () {
      final entries = [
        _entry(id: 'a', amount: 1000, direction: MoneyDirection.income),
        _entry(
          id: 'future',
          amount: 5000,
          direction: MoneyDirection.income,
          happenedAt: DateTime(2026, 12, 25),
        ),
      ];

      // Zakat is owed on what is held, so a post-dated entry must not inflate
      // the balance until its date arrives.
      expect(
        MoneyLedger.balanceOf(
          entries,
          accountId: MoneyAccount.defaultId,
          currency: 'USD',
          asOf: DateTime(2026, 9, 7),
        ),
        1000,
      );
      expect(
        MoneyLedger.balanceOf(
          entries,
          accountId: MoneyAccount.defaultId,
          currency: 'USD',
          asOf: DateTime(2026, 12, 26),
        ),
        6000,
      );
    });
  });

  group('ranges', () {
    test('a month includes its first instant and excludes the next', () {
      final september = DateRange.month(DateTime(2026, 9, 15));

      expect(september.contains(DateTime(2026, 9, 1)), isTrue);
      expect(september.contains(DateTime(2026, 9, 30, 23, 59)), isTrue);
      expect(september.contains(DateTime(2026, 10, 1)), isFalse);
      expect(september.contains(DateTime(2026, 8, 31, 23, 59)), isFalse);
    });

    test('a December month rolls into the next year', () {
      final december = DateRange.month(DateTime(2026, 12, 10));

      expect(december.end, DateTime(2027, 1, 1));
      expect(december.contains(DateTime(2026, 12, 31, 23, 59)), isTrue);
    });

    test('filtering keeps only what falls inside', () {
      final entries = [
        _entry(id: 'aug', happenedAt: DateTime(2026, 8, 30)),
        _entry(id: 'sep', happenedAt: DateTime(2026, 9, 6)),
        _entry(id: 'oct', happenedAt: DateTime(2026, 10, 1)),
      ];

      final september = MoneyLedger.inRange(
        entries,
        DateRange.month(DateTime(2026, 9, 6)),
      );

      expect(september.map((entry) => entry.id), ['sep']);
    });
  });

  group('by category', () {
    test('groups one direction, largest first', () {
      final totals = MoneyLedger.byCategory(
        [
          _entry(id: 'a', amount: 30, categoryId: 'expense.groceries'),
          _entry(id: 'b', amount: 120, categoryId: 'expense.rent'),
          _entry(id: 'c', amount: 20, categoryId: 'expense.groceries'),
          _entry(
            id: 'd',
            amount: 999,
            direction: MoneyDirection.income,
            categoryId: 'income.salary',
          ),
        ],
        direction: MoneyDirection.expense,
        displayCurrency: 'USD',
      );

      expect(totals.map((total) => total.categoryId), [
        'expense.rent',
        'expense.groceries',
      ]);
      expect(totals.first.amount, 120);
      expect(totals.last.amount, 50);
    });

    test('entries saved without a category still get counted', () {
      final totals = MoneyLedger.byCategory(
        [_entry(amount: 15)],
        direction: MoneyDirection.expense,
        displayCurrency: 'USD',
      );

      // Capture allows skipping the category, so the breakdown has to have
      // somewhere to put it rather than losing the money.
      expect(totals.single.categoryId, isNull);
      expect(totals.single.amount, 15);
    });
  });

  test('newest first is the order screens read in', () {
    final sorted = MoneyLedger.newestFirst([
      _entry(id: 'old', happenedAt: DateTime(2026, 9, 1)),
      _entry(id: 'new', happenedAt: DateTime(2026, 9, 6)),
      _entry(id: 'mid', happenedAt: DateTime(2026, 9, 3)),
    ]);

    expect(sorted.map((entry) => entry.id), ['new', 'mid', 'old']);
  });
}
