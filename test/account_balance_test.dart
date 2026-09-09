import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/services/cash_account_migration.dart';
import 'package:moniz/services/money_ledger.dart';

const planner = CashAccountMigrationPlanner();

MoneyEntry _entry({
  required double amount,
  MoneyDirection direction = MoneyDirection.expense,
  required DateTime on,
  String currency = 'USD',
}) {
  return MoneyEntry(
    id: '$direction-$amount-${on.toIso8601String()}',
    amount: amount,
    direction: direction,
    currency: currency,
    happenedAt: on,
  );
}

void main() {
  group('opening balance', () {
    const account = MoneyAccount(
      id: MoneyAccount.defaultId,
      label: 'Wallet',
      openingBalance: 1000,
    );

    test('an account with no entries is still worth what it started with', () {
      // Somebody who has been saving for years should not see an empty wallet
      // until they have logged a year of entries.
      expect(
        MoneyLedger.balanceOf(
          const [],
          accountId: MoneyAccount.defaultId,
          currency: 'USD',
          account: account,
          asOf: DateTime(2026, 9, 7),
        ),
        1000,
      );
    });

    test('entries move it from there', () {
      final balance = MoneyLedger.balanceOf(
        [
          _entry(amount: 200, on: DateTime(2026, 9, 1)),
          _entry(
            amount: 50,
            direction: MoneyDirection.income,
            on: DateTime(2026, 9, 2),
          ),
        ],
        accountId: MoneyAccount.defaultId,
        currency: 'USD',
        account: account,
        asOf: DateTime(2026, 9, 7),
      );

      expect(balance, 850);
    });

    test('without an account the balance is entries alone', () {
      // The existing behaviour has to survive: nothing has an account yet.
      expect(
        MoneyLedger.balanceOf(
          [_entry(amount: 200, on: DateTime(2026, 9, 1))],
          accountId: MoneyAccount.defaultId,
          currency: 'USD',
          asOf: DateTime(2026, 9, 7),
        ),
        -200,
      );
    });

    test('it converts into the currency being asked for', () {
      final balance = MoneyLedger.balanceOf(
        const [],
        accountId: MoneyAccount.defaultId,
        currency: 'AED',
        account: account,
        asOf: DateTime(2026, 9, 7),
      );

      expect(balance, closeTo(3672.5, 0.01));
    });
  });

  group('entries around the opening date', () {
    final account = MoneyAccount(
      id: MoneyAccount.defaultId,
      label: 'Wallet',
      openingBalance: 1000,
      openedOn: DateTime(2026, 9, 1),
    );

    test('an entry before it is already inside it and not counted twice', () {
      final balance = MoneyLedger.balanceOf(
        [_entry(amount: 500, on: DateTime(2026, 8, 20))],
        accountId: MoneyAccount.defaultId,
        currency: 'USD',
        account: account,
        asOf: DateTime(2026, 9, 7),
      );

      expect(balance, 1000);
    });

    test('an entry on the opening day counts', () {
      final balance = MoneyLedger.balanceOf(
        [_entry(amount: 100, on: DateTime(2026, 9, 1, 10))],
        accountId: MoneyAccount.defaultId,
        currency: 'USD',
        account: account,
        asOf: DateTime(2026, 9, 7),
      );

      expect(balance, 900);
    });

    test('the balance is not counted before it was known', () {
      expect(
        MoneyLedger.balanceOf(
          const [],
          accountId: MoneyAccount.defaultId,
          currency: 'USD',
          account: account,
          asOf: DateTime(2026, 8, 15),
        ),
        0,
      );
    });
  });

  group('migrating cash holdings', () {
    Asset cash({
      String id = 'cash',
      double amount = 4200,
      String currency = 'USD',
      DateTime? boughtDate,
      DateTime? soldDate,
      String? note,
    }) {
      return Asset(
        id: id,
        type: AssetType.cash,
        amount: amount,
        unit: currency,
        currency: currency,
        boughtDate: boughtDate,
        soldDate: soldDate,
        soldPrice: soldDate == null ? null : amount,
        note: note,
      );
    }

    test('a cash holding becomes an account starting at its amount', () {
      final migration = planner.plan(
        assets: [cash(boughtDate: DateTime(2026, 1, 1))],
        existingAccounts: const [],
      );

      final account = migration.accounts.single;
      expect(account.openingBalance, 4200);
      expect(account.currency, 'USD');
      expect(account.openedOn, DateTime(2026, 1, 1));
      expect(migration.migratedAssetIds, ['cash']);
    });

    test('the note becomes the name, or it falls back', () {
      expect(
        planner
            .plan(
              assets: [cash(note: 'Emergency fund')],
              existingAccounts: const [],
            )
            .accounts
            .single
            .label,
        'Emergency fund',
      );
      expect(
        planner
            .plan(assets: [cash()], existingAccounts: const [])
            .accounts
            .single
            .label,
        'Cash',
      );
    });

    test('gold and silver are left alone', () {
      final migration = planner.plan(
        assets: [
          const Asset(id: 'g', type: AssetType.gold, amount: 20, unit: 'g'),
        ],
        existingAccounts: const [],
      );

      expect(migration.isEmpty, isTrue);
      expect(migration.skipped, isEmpty);
    });

    test('a sold holding is not resurrected as a balance', () {
      final migration = planner.plan(
        assets: [cash(soldDate: DateTime(2026, 5, 1))],
        existingAccounts: const [],
      );

      expect(migration.accounts, isEmpty);
      expect(migration.skipped['cash'], CashAccountMigrationPlanner.soldSkip);
    });

    test('an empty holding carries nothing over', () {
      final migration = planner.plan(
        assets: [cash(amount: 0)],
        existingAccounts: const [],
      );

      expect(migration.accounts, isEmpty);
      expect(migration.skipped['cash'], CashAccountMigrationPlanner.zeroSkip);
    });

    test('running it twice does not make a second account', () {
      final first = planner.plan(
        assets: [cash()],
        existingAccounts: const [],
      );
      final second = planner.plan(
        assets: [cash()],
        existingAccounts: first.accounts,
      );

      expect(second.accounts, isEmpty);
      expect(
        second.skipped['cash'],
        CashAccountMigrationPlanner.alreadyMigratedSkip,
      );
    });

    test('re-running does not reset a balance that has since moved', () {
      final migrated = planner.plan(
        assets: [cash()],
        existingAccounts: const [],
      ).accounts.single;
      final spentSince = migrated.copyWith(openingBalance: 10);

      final again = planner.plan(
        assets: [cash()],
        existingAccounts: [spentSince],
      );

      expect(again.accounts, isEmpty);
    });

    test('a holding with no start date still migrates, open-dated', () {
      // Its entries cannot be double counted, because there is no date to be
      // before.
      final account = planner
          .plan(assets: [cash()], existingAccounts: const [])
          .accounts
          .single;

      expect(account.openedOn, isNull);
      expect(account.openingBalance, 4200);
    });

    test('several holdings each get their own account', () {
      final migration = planner.plan(
        assets: [
          cash(id: 'a', amount: 100),
          cash(id: 'b', amount: 200, currency: 'AED'),
        ],
        existingAccounts: const [],
      );

      expect(migration.accounts, hasLength(2));
      expect(migration.accounts.map((a) => a.id).toSet(), {
        'cash:a',
        'cash:b',
      });
      expect(migration.accounts.last.currency, 'AED');
    });
  });

  test('a migrated account values the same as the holding did', () {
    final account = planner
        .plan(
          assets: [
            const Asset(
              id: 'cash',
              type: AssetType.cash,
              amount: 4200,
              unit: 'USD',
              currency: 'USD',
            ),
          ],
          existingAccounts: const [],
        )
        .accounts
        .single;

    // The point of the whole exercise: the money does not change value by
    // moving from a holding into an account.
    expect(
      MoneyLedger.balanceOf(
        const [],
        accountId: account.id,
        currency: 'AED',
        account: account,
        prices: MetalPriceSnapshot(
          goldPerGramUsd: 100,
          silverPerGramUsd: 1,
          priceTimestamp: DateTime.utc(2026, 9, 7),
          fetchedAt: DateTime.utc(2026, 9, 7),
        ),
      ),
      closeTo(4200 * 3.6725, 0.01),
    );
  });

  group('balance across wallets', () {
    const chequing = MoneyAccount(
      id: 'cash:chequing',
      label: 'Chequing',
      openingBalance: 5000,
    );
    const inHand = MoneyAccount(
      id: 'cash:hand',
      label: 'Cash in hand',
      openingBalance: 200,
    );
    const started = MoneyAccount(id: MoneyAccount.defaultId, label: 'Wallet');

    MoneyEntry against(String accountId, double amount) {
      return MoneyEntry(
        id: '$accountId-$amount',
        amount: amount,
        direction: MoneyDirection.expense,
        currency: 'USD',
        happenedAt: DateTime(2026, 9, 1),
        accountId: accountId,
      );
    }

    test('every wallet counts, not just the one entries started in', () {
      expect(
        MoneyLedger.balanceAcross(
          const [],
          accounts: const [started, chequing, inHand],
          currency: 'USD',
          asOf: DateTime(2026, 9, 7),
        ),
        5200,
      );
    });

    test('spending comes out of the wallet it was logged against', () {
      expect(
        MoneyLedger.balanceAcross(
          [against('cash:chequing', 300), against('cash:hand', 50)],
          accounts: const [started, chequing, inHand],
          currency: 'USD',
          asOf: DateTime(2026, 9, 7),
        ),
        4850,
      );
    });

    test('an entry against no known wallet is not counted twice', () {
      // It is counted once, under its own wallet, or not at all — never once
      // per wallet in the list.
      expect(
        MoneyLedger.balanceAcross(
          [against('cash:gone', 100)],
          accounts: const [started, chequing],
          currency: 'USD',
          asOf: DateTime(2026, 9, 7),
        ),
        5000,
      );
    });

    test('no wallets is zero, not a crash', () {
      expect(
        MoneyLedger.balanceAcross(
          [against('cash:chequing', 300)],
          accounts: const [],
          currency: 'USD',
          asOf: DateTime(2026, 9, 7),
        ),
        0,
      );
    });

    test('wallets in different currencies are converted before adding', () {
      const dirhams = MoneyAccount(
        id: 'cash:aed',
        label: 'Dubai',
        currency: 'AED',
        openingBalance: 3672.5,
      );
      expect(
        MoneyLedger.balanceAcross(
          const [],
          accounts: const [chequing, dirhams],
          currency: 'USD',
          asOf: DateTime(2026, 9, 7),
        ),
        closeTo(6000, 0.01),
      );
    });
  });

  group('telling migrated wallets apart', () {
    Asset cash(String id, {String? note}) {
      return Asset(
        id: id,
        type: AssetType.cash,
        amount: 100,
        unit: 'USD',
        currency: 'USD',
        note: note,
      );
    }

    test('two unlabelled holdings do not both come out as Cash', () {
      // A picker showing two identical chips is not offering a choice.
      final migration = planner.plan(
        assets: [cash('a'), cash('b')],
        existingAccounts: const [],
      );

      expect(
        migration.accounts.map((account) => account.label),
        ['Cash', 'Cash 2'],
      );
    });

    test('a holding does not take a name an account already has', () {
      final migration = planner.plan(
        assets: [cash('a', note: 'Wallet')],
        existingAccounts: const [
          MoneyAccount(id: MoneyAccount.defaultId, label: 'Wallet'),
        ],
      );

      expect(migration.accounts.single.label, 'Wallet 2');
    });

    test('a name of its own is left alone', () {
      final migration = planner.plan(
        assets: [cash('a', note: 'Chequing'), cash('b', note: 'Savings')],
        existingAccounts: const [
          MoneyAccount(id: MoneyAccount.defaultId, label: 'Wallet'),
        ],
      );

      expect(
        migration.accounts.map((account) => account.label),
        ['Chequing', 'Savings'],
      );
    });

    test('the clash is judged without regard to case', () {
      final migration = planner.plan(
        assets: [cash('a', note: 'chequing')],
        existingAccounts: const [
          MoneyAccount(id: 'other', label: 'Chequing'),
        ],
      );

      expect(migration.accounts.single.label, 'chequing 2');
    });
  });
}
