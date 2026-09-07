import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/services/money_ledger.dart';

MetalPriceSnapshot _prices({double? eur, double? cad}) {
  return MetalPriceSnapshot(
    goldPerGramUsd: 100,
    silverPerGramUsd: 1,
    priceTimestamp: DateTime.utc(2026, 9, 7),
    fetchedAt: DateTime.utc(2026, 9, 7),
    eurToUsd: eur,
    cadToUsd: cad,
  );
}

MoneyEntry _entry({
  double amount = 100,
  String currency = 'EUR',
  double? usdRate,
}) {
  return MoneyEntry(
    id: 'e',
    amount: amount,
    direction: MoneyDirection.expense,
    currency: currency,
    happenedAt: DateTime(2026, 3, 1),
    usdRate: usdRate,
  );
}

void main() {
  group('the recorded rate wins', () {
    test('a past entry keeps the value it had, not today\'s', () {
      // Recorded in March at 1.20, read today when the euro is at 1.05.
      final value = MoneyLedger.valueOf(
        _entry(usdRate: 1.20),
        displayCurrency: 'USD',
        prices: _prices(eur: 1.05),
      );

      expect(value, closeTo(120, 0.001));
    });

    test('without a recorded rate the live one is used', () {
      // Entries saved before rates were frozen still have to convert.
      final value = MoneyLedger.valueOf(
        _entry(),
        displayCurrency: 'USD',
        prices: _prices(eur: 1.05),
      );

      expect(value, closeTo(105, 0.001));
    });

    test('no rate anywhere means the entry is excluded, not guessed', () {
      expect(
        MoneyLedger.valueOf(
          _entry(),
          displayCurrency: 'USD',
          prices: _prices(),
        ),
        isNull,
      );
    });
  });

  group('an entry read in its own currency', () {
    test('is never converted, however the rate has moved', () {
      // The trap: frozen rate divided by today's rate would drift EUR 100
      // away from EUR 100.
      final value = MoneyLedger.valueOf(
        _entry(usdRate: 1.20),
        displayCurrency: 'EUR',
        prices: _prices(eur: 1.05),
      );

      expect(value, 100);
    });

    test('holds even with no rates at all', () {
      final value = MoneyLedger.valueOf(
        _entry(usdRate: 1.20),
        displayCurrency: 'EUR',
        prices: _prices(),
      );

      expect(value, 100);
    });

    test('and USD in USD is untouched', () {
      expect(
        MoneyLedger.valueOf(
          _entry(currency: 'USD', usdRate: 1),
          displayCurrency: 'USD',
        ),
        100,
      );
    });
  });

  test('the display side uses today\'s rate, not a frozen one', () {
    // Only the entry is history. The currency it is read in is a present
    // choice, so CAD moving changes what the March euros are shown as.
    final value = MoneyLedger.valueOf(
      _entry(usdRate: 1.20),
      displayCurrency: 'CAD',
      prices: _prices(eur: 1.05, cad: 0.75),
    );

    expect(value, closeTo(160, 0.001));
  });

  test('totals add up from the recorded rates', () {
    final totals = MoneyLedger.totals(
      [
        _entry(amount: 100, usdRate: 1.20),
        MoneyEntry(
          id: 'usd',
          amount: 50,
          direction: MoneyDirection.expense,
          happenedAt: DateTime(2026, 3, 2),
          usdRate: 1,
        ),
      ],
      displayCurrency: 'USD',
      prices: _prices(eur: 1.05),
    );

    expect(totals.expense, closeTo(170, 0.001));
    expect(totals.isComplete, isTrue);
  });

  test('an entry with no usable rate is counted as excluded', () {
    final totals = MoneyLedger.totals(
      [_entry(), _entry(currency: 'USD')],
      displayCurrency: 'USD',
      prices: _prices(),
    );

    expect(totals.expense, 100);
    expect(totals.excludedEntryCount, 1);
    expect(totals.isComplete, isFalse);
  });

  test('a balance uses recorded rates too', () {
    final balance = MoneyLedger.balanceOf(
      [
        MoneyEntry(
          id: 'in',
          amount: 100,
          direction: MoneyDirection.income,
          currency: 'EUR',
          happenedAt: DateTime(2026, 3, 1),
          usdRate: 1.20,
        ),
      ],
      accountId: MoneyAccount.defaultId,
      currency: 'USD',
      asOf: DateTime(2026, 9, 7),
      prices: _prices(eur: 1.05),
    );

    expect(balance, closeTo(120, 0.001));
  });
}
