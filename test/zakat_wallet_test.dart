import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/services/cash_account_migration.dart';
import 'package:moniz/services/money_ledger.dart';
import 'package:moniz/services/zakat_engine.dart';

/// The holding start date, and so the start of every hawl year below.
final _boughtOn = DateTime(2025, 1, 1);

/// One lunar year on from [_boughtOn]: the first anniversary.
final _dueOn = _boughtOn.add(const Duration(days: 354));

MetalPriceSnapshot _prices() {
  return MetalPriceSnapshot(
    goldPerGramUsd: 100,
    // A silver nisab of 612.36g at $1/g puts the threshold at $612.36.
    silverPerGramUsd: 1,
    priceTimestamp: DateTime.utc(2026, 1, 1),
    fetchedAt: DateTime.utc(2026, 1, 1),
  );
}

final _cash = Asset(
  id: 'chequing',
  type: AssetType.cash,
  amount: 5000,
  unit: 'USD',
  currency: 'USD',
  boughtDate: _boughtOn,
);

final _wallet = MoneyAccount(
  id: CashAccountMigrationPlanner.accountIdFor('chequing'),
  label: 'Chequing',
  openingBalance: 5000,
  openedOn: _boughtOn,
);

MoneyEntry _spend(double amount, DateTime on) {
  return MoneyEntry(
    id: 'out-$amount-${on.toIso8601String()}',
    amount: amount,
    direction: MoneyDirection.expense,
    currency: 'USD',
    happenedAt: on,
    accountId: _wallet.id,
  );
}

MoneyEntry _earn(double amount, DateTime on) {
  return MoneyEntry(
    id: 'in-$amount-${on.toIso8601String()}',
    amount: amount,
    direction: MoneyDirection.income,
    currency: 'USD',
    happenedAt: on,
    accountId: _wallet.id,
  );
}

ZakatResult _perHolding({
  required List<MoneyEntry> entries,
  List<Asset>? assets,
  DateTime? today,
}) {
  return ZakatEngine.calculate(
    assets: assets ?? [_cash],
    prices: _prices(),
    settings: const ZakatSettings(
      scheduleMode: ZakatScheduleMode.individualDueDates,
    ),
    payments: const {},
    today: today ?? _dueOn,
    moneyEntries: entries,
    accounts: [_wallet],
  );
}

void main() {
  group('the lowest the wallet got', () {
    test('zakat is on what stayed all year, not on the closing balance', () {
      // Down to 1,200 in the middle, back up to 4,200 by the anniversary.
      // Only the 1,200 was held for the whole year.
      final result = _perHolding(
        entries: [
          _spend(3800, DateTime(2025, 5, 1)),
          _earn(3000, DateTime(2025, 9, 1)),
        ],
      );

      expect(result.eligibleWealthUsd, 1200);
      expect(result.amountDueUsd, closeTo(30, 0.0001));
    });

    test('money that came and went does not raise the figure', () {
      // A salary that lands and is spent was never held for the year.
      final result = _perHolding(
        entries: [
          _earn(9000, DateTime(2025, 4, 1)),
          _spend(9000, DateTime(2025, 4, 20)),
        ],
      );

      expect(result.eligibleWealthUsd, 5000);
    });

    test('a wallet that recovered is still assessed on the dip', () {
      // Down to 1,000 and fully back to 5,000 by the anniversary. Assessing
      // the closing balance would charge zakat on 4,000 that spent most of
      // the year outside the account.
      final result = _perHolding(
        entries: [
          _spend(4000, DateTime(2025, 5, 1)),
          _earn(4000, DateTime(2025, 9, 1)),
        ],
      );

      expect(result.eligibleWealthUsd, 1000);
    });

    test('the lowest of several dips is the one that counts', () {
      final result = _perHolding(
        entries: [
          _spend(2000, DateTime(2025, 3, 1)),
          _earn(2000, DateTime(2025, 4, 1)),
          _spend(4200, DateTime(2025, 7, 1)),
          _earn(4200, DateTime(2025, 8, 1)),
          _spend(1000, DateTime(2025, 10, 1)),
          _earn(1000, DateTime(2025, 11, 1)),
        ],
      );

      expect(result.eligibleWealthUsd, 800);
    });

    test('a wallet that only ever grew is assessed on where it started', () {
      // Nothing dipped, so the low point is the opening balance — the part
      // that was there for the whole year.
      final result = _perHolding(
        entries: [
          _earn(2000, DateTime(2025, 4, 1)),
          _earn(3000, DateTime(2025, 8, 1)),
        ],
      );

      expect(result.eligibleWealthUsd, 5000);
    });

    test('an untouched wallet is assessed on the whole balance', () {
      expect(_perHolding(entries: const []).eligibleWealthUsd, 5000);
    });

    test('the holding amount is ignored once a wallet backs it', () {
      // The stored 5,000 is a number kept by hand. The wallet is what
      // actually happened.
      final result = _perHolding(
        entries: [_spend(4000, DateTime(2025, 6, 1))],
      );

      expect(result.assessments.single.asset.amount, 5000);
      expect(result.eligibleWealthUsd, 1000);
    });

    test('spending can take the wallet under nisab', () {
      final result = _perHolding(
        entries: [_spend(4500, DateTime(2025, 6, 1))],
      );

      // 500 is below the 612.36 silver nisab, so nothing is owed.
      expect(result.eligibleWealthUsd, 500);
      expect(result.amountDueUsd, 0);
    });

    test('an overdrawn wallet is a debt, not negative wealth', () {
      final result = _perHolding(
        entries: [_spend(9000, DateTime(2025, 6, 1))],
      );

      expect(result.eligibleWealthUsd, 0);
      expect(result.amountDueUsd, 0);
    });

    test('the year assessed is the one that just completed', () {
      // A dip after the anniversary belongs to the next year, not this one.
      final result = _perHolding(
        entries: [_spend(4900, _dueOn.add(const Duration(days: 10)))],
        today: _dueOn.add(const Duration(days: 20)),
      );

      expect(result.eligibleWealthUsd, 5000);
    });

    test('the row says why the figure is not the holding amount', () {
      final result = _perHolding(
        entries: [_spend(3800, DateTime(2025, 5, 1))],
      );

      expect(
        result.assessments.single.valuationNote,
        ZakatEngine.lowestBalanceNote,
      );
    });
  });

  group('Ramadan counts everything on the day', () {
    ZakatResult ramadan({required List<MoneyEntry> entries, DateTime? today}) {
      return ZakatEngine.calculate(
        assets: [_cash],
        prices: _prices(),
        settings: ZakatSettings(nextRamadanDueDate: DateTime(2025, 3, 1)),
        payments: const {},
        today: today ?? DateTime(2025, 3, 1),
        moneyEntries: entries,
        accounts: [_wallet],
      );
    }

    test('the balance on the date, not the low point before it', () {
      // Dipped to 1,000 in January and recovered. Ramadan does not care:
      // it fixes one day for the whole portfolio.
      final result = ramadan(
        entries: [
          _spend(4000, DateTime(2025, 1, 15)),
          _earn(3500, DateTime(2025, 2, 15)),
        ],
      );

      expect(result.eligibleWealthUsd, 4500);
      expect(result.assessments.single.valuationNote,
          ZakatEngine.ramadanWalletNote);
    });

    test('spending after the date does not reduce what was owed on it', () {
      final result = ramadan(
        entries: [_spend(4000, DateTime(2025, 6, 1))],
        today: DateTime(2025, 7, 1),
      );

      expect(result.eligibleWealthUsd, 5000);
    });
  });

  group('holdings without a wallet are untouched', () {
    test('an unmigrated cash holding still uses its own amount', () {
      final result = ZakatEngine.calculate(
        assets: [_cash],
        prices: _prices(),
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: const {},
        today: _dueOn,
        moneyEntries: [_spend(4000, DateTime(2025, 6, 1))],
        accounts: const [],
      );

      expect(result.eligibleWealthUsd, 5000);
      expect(result.assessments.single.valuationNote, isNull);
    });

    test('gold is not assessed from a wallet', () {
      final result = ZakatEngine.calculate(
        assets: [
          Asset(
            id: 'chequing',
            type: AssetType.gold,
            amount: 20,
            unit: 'g',
            purity: 100,
            boughtDate: _boughtOn,
          ),
        ],
        prices: _prices(),
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: const {},
        today: _dueOn,
        moneyEntries: [_spend(1000, DateTime(2025, 6, 1))],
        // Same id as the gold holding, so only the type keeps them apart.
        accounts: [_wallet],
      );

      expect(result.eligibleWealthUsd, 2000);
      expect(result.assessments.single.valuationNote, isNull);
    });
  });

  group('minimumBalanceOf', () {
    test('an entry exactly on the closing edge counts', () {
      expect(
        MoneyLedger.minimumBalanceOf(
          [_spend(1000, _dueOn)],
          accountId: _wallet.id,
          currency: 'USD',
          from: _boughtOn,
          to: _dueOn,
          account: _wallet,
        ),
        4000,
      );
    });

    test('an entry after the window is outside it', () {
      expect(
        MoneyLedger.minimumBalanceOf(
          [_spend(1000, _dueOn.add(const Duration(days: 1)))],
          accountId: _wallet.id,
          currency: 'USD',
          from: _boughtOn,
          to: _dueOn,
          account: _wallet,
        ),
        5000,
      );
    });

    test('spending before the window opened is already in the opening', () {
      // The window opens partway through, so the balance it starts from
      // already reflects everything before it.
      expect(
        MoneyLedger.minimumBalanceOf(
          [_spend(1000, DateTime(2025, 2, 1))],
          accountId: _wallet.id,
          currency: 'USD',
          from: DateTime(2025, 6, 1),
          to: _dueOn,
          account: _wallet,
        ),
        4000,
      );
    });

    test('another wallet\'s spending is not counted', () {
      final other = MoneyEntry(
        id: 'other',
        amount: 4000,
        direction: MoneyDirection.expense,
        currency: 'USD',
        happenedAt: DateTime(2025, 6, 1),
        accountId: 'cash:somewhere-else',
      );

      expect(
        MoneyLedger.minimumBalanceOf(
          [other],
          accountId: _wallet.id,
          currency: 'USD',
          from: _boughtOn,
          to: _dueOn,
          account: _wallet,
        ),
        5000,
      );
    });
  });
}
