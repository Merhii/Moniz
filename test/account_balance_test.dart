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
}
