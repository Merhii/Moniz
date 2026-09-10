import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/services/cash_account_migration.dart';
import 'package:moniz/services/zakat_engine.dart';

final _openedOn = DateTime(2025, 1, 1);
final _dueOn = _openedOn.add(const Duration(days: 354));

MetalPriceSnapshot _prices() {
  return MetalPriceSnapshot(
    goldPerGramUsd: 100,
    silverPerGramUsd: 1,
    priceTimestamp: DateTime.utc(2026, 1, 1),
    fetchedAt: DateTime.utc(2026, 1, 1),
  );
}

/// The wallet every install is seeded with. Nothing in Holdings stands for it.
final _startingWallet = MoneyAccount(
  id: MoneyAccount.defaultId,
  label: 'Wallet',
  openingBalance: 4000,
  openedOn: _openedOn,
);

MoneyEntry _entry(
  double amount,
  DateTime on, {
  MoneyDirection direction = MoneyDirection.expense,
  String accountId = MoneyAccount.defaultId,
}) {
  return MoneyEntry(
    id: '$accountId-$direction-$amount-${on.toIso8601String()}',
    amount: amount,
    direction: direction,
    currency: 'USD',
    happenedAt: on,
    accountId: accountId,
  );
}

ZakatResult _perHolding({
  List<Asset> assets = const [],
  List<MoneyAccount> accounts = const [],
  List<MoneyEntry> entries = const [],
  Map<String, ZakatPaymentRecord> payments = const {},
  DateTime? today,
}) {
  return ZakatEngine.calculate(
    assets: assets,
    prices: _prices(),
    settings: const ZakatSettings(
      scheduleMode: ZakatScheduleMode.individualDueDates,
    ),
    payments: payments,
    today: today ?? _dueOn,
    moneyEntries: entries,
    accounts: accounts,
  );
}

void main() {
  group('a wallet no holding stands for', () {
    test('is counted instead of being invisible', () {
      // The whole gap: this money was outside zakat entirely, because the
      // engine only ever walked Holdings.
      final result = _perHolding(accounts: [_startingWallet]);

      expect(result.eligibleWealthUsd, 4000);
      expect(result.amountDueUsd, closeTo(100, 0.0001));
    });

    test('is assessed on the lowest it got, like any other wallet', () {
      final result = _perHolding(
        accounts: [_startingWallet],
        entries: [
          _entry(3000, DateTime(2025, 5, 1)),
          _entry(
            3000,
            DateTime(2025, 9, 1),
            direction: MoneyDirection.income,
          ),
        ],
      );

      expect(result.eligibleWealthUsd, 1000);
      expect(
        result.assessments.single.valuationNote,
        ZakatEngine.lowestBalanceNote,
      );
    });

    test('waits out its own lunar year before it is due', () {
      final result = _perHolding(
        accounts: [_startingWallet],
        today: _dueOn.subtract(const Duration(days: 1)),
      );

      expect(result.assessments.single.isIncluded, isFalse);
      expect(
        result.assessments.single.exclusionReason,
        ZakatEngine.hawlNotReachedExclusion,
      );
      expect(result.amountDueUsd, 0);
    });

    test('needs a start date before the hawl can be measured', () {
      final result = _perHolding(
        accounts: const [
          MoneyAccount(
            id: MoneyAccount.defaultId,
            label: 'Wallet',
            openingBalance: 4000,
          ),
        ],
      );

      expect(
        result.assessments.single.exclusionReason,
        ZakatEngine.missingWalletStartExclusion,
      );
      expect(result.eligibleWealthUsd, 0);
    });

    test('is named after itself on screen', () {
      final result = _perHolding(accounts: [_startingWallet]);

      expect(result.assessments.single.label, 'Wallet');
      expect(result.assessments.single.asset, isNull);
    });

    test('files its payment apart from any holding', () {
      final result = _perHolding(accounts: [_startingWallet]);

      expect(result.assessments.single.referenceId, 'wallet:default');
    });

    test('a payment settles it and moves the year on', () {
      final paidAt = _dueOn.add(const Duration(days: 2));
      final result = _perHolding(
        accounts: [_startingWallet],
        payments: {
          'wallet:default': ZakatPaymentRecord(
            referenceId: 'wallet:default',
            paidAt: paidAt,
            amountUsd: 100,
          ),
        },
        today: paidAt.add(const Duration(days: 1)),
      );

      expect(result.assessments.single.isIncluded, isFalse);
      expect(result.amountDueUsd, 0);
    });
  });

  group('not counted twice', () {
    final cash = Asset(
      id: 'chequing',
      type: AssetType.cash,
      amount: 5000,
      unit: 'USD',
      currency: 'USD',
      boughtDate: _openedOn,
    );
    final migrated = MoneyAccount(
      id: CashAccountMigrationPlanner.accountIdFor('chequing'),
      label: 'Chequing',
      openingBalance: 5000,
      openedOn: _openedOn,
    );

    test('a migrated wallet is assessed through its holding, once', () {
      final result = _perHolding(assets: [cash], accounts: [migrated]);

      expect(result.assessments.length, 1);
      expect(result.eligibleWealthUsd, 5000);
    });

    test('the starting wallet is still counted beside it', () {
      final result = _perHolding(
        assets: [cash],
        accounts: [migrated, _startingWallet],
      );

      expect(result.eligibleWealthUsd, 9000);
    });

    test('selling the holding does not make the wallet money vanish', () {
      // The holding drops out as sold. If the wallet stayed tied to it, the
      // money in the wallet would leave the calculation with it.
      final sold = Asset(
        id: 'chequing',
        type: AssetType.cash,
        amount: 5000,
        unit: 'USD',
        currency: 'USD',
        boughtDate: _openedOn,
        soldDate: DateTime(2025, 6, 1),
        soldPrice: 5000,
      );

      final result = _perHolding(assets: [sold], accounts: [migrated]);

      expect(result.eligibleWealthUsd, 5000);
      expect(
        result.assessments.where((a) => a.wallet != null).single.valueUsd,
        5000,
      );
    });
  });

  group('quiet about wallets that hold nothing', () {
    test('an untouched seeded wallet is not a row on the zakat screen', () {
      final result = _perHolding(
        accounts: const [
          MoneyAccount(id: MoneyAccount.defaultId, label: 'Wallet'),
        ],
      );

      expect(result.assessments, isEmpty);
    });

    test('but one that has been used shows even at zero', () {
      final result = _perHolding(
        accounts: const [
          MoneyAccount(id: MoneyAccount.defaultId, label: 'Wallet'),
        ],
        entries: [
          _entry(
            50,
            DateTime(2025, 5, 1),
            direction: MoneyDirection.income,
          ),
          _entry(50, DateTime(2025, 6, 1)),
        ],
      );

      expect(result.assessments, hasLength(1));
    });
  });

  group('Ramadan', () {
    test('counts the starting wallet in full on the date', () {
      final result = ZakatEngine.calculate(
        assets: const [],
        prices: _prices(),
        settings: ZakatSettings(nextRamadanDueDate: DateTime(2025, 6, 1)),
        payments: const {},
        today: DateTime(2025, 6, 1),
        moneyEntries: [
          _entry(3000, DateTime(2025, 3, 1)),
          _entry(
            3000,
            DateTime(2025, 4, 1),
            direction: MoneyDirection.income,
          ),
        ],
        accounts: [_startingWallet],
      );

      // Dipped to 1,000 in March and recovered by April. Ramadan reads the
      // balance on the day, so the dip is irrelevant — 4,000, not 1,000.
      expect(result.eligibleWealthUsd, 4000);
      expect(
        result.assessments.single.valuationNote,
        ZakatEngine.ramadanWalletNote,
      );
    });
  });
}
