import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/services/cash_account_migration.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_cash_mig_');
    Hive.init(hiveDirectory.path);
    registerMonizAdapters();
    await Hive.openBox<Asset>('assets');
    await Hive.openBox<MoneyAccount>('moneyAccounts');
  });

  setUp(() async {
    await Hive.box<Asset>('assets').clear();
    await Hive.box<MoneyAccount>('moneyAccounts').clear();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  Box<Asset> assets() => Hive.box<Asset>('assets');
  Box<MoneyAccount> accounts() => Hive.box<MoneyAccount>('moneyAccounts');

  Future<void> putCash(
    String id, {
    required double amount,
    String currency = 'USD',
    String? note,
    DateTime? boughtDate,
    DateTime? soldDate,
  }) {
    return assets().put(
      id,
      Asset(
        id: id,
        type: AssetType.cash,
        amount: amount,
        unit: currency,
        currency: currency,
        note: note,
        boughtDate: boughtDate,
        soldDate: soldDate,
        soldPrice: soldDate == null ? null : amount,
      ),
    );
  }

  test('a cash holding becomes a wallet with that money already in it',
      () async {
    await putCash(
      'chequing',
      amount: 5000,
      note: 'Chequing',
      boughtDate: DateTime(2026, 1, 4),
    );

    await migrateCashHoldingsToAccounts();

    final account = accounts().get(
      CashAccountMigrationPlanner.accountIdFor('chequing'),
    );
    expect(account, isNotNull);
    expect(account!.label, 'Chequing');
    expect(account.openingBalance, 5000);
    expect(account.currency, 'USD');
    expect(account.openedOn, DateTime(2026, 1, 4));
  });

  test('the holding itself is left alone', () async {
    await putCash('chequing', amount: 5000, note: 'Chequing');

    await migrateCashHoldingsToAccounts();

    final asset = assets().get('chequing');
    expect(asset, isNotNull);
    expect(asset!.amount, 5000);
    expect(asset.type, AssetType.cash);
  });

  test('running again does not reset a balance that has since moved',
      () async {
    await putCash('chequing', amount: 5000, note: 'Chequing');
    await migrateCashHoldingsToAccounts();

    final id = CashAccountMigrationPlanner.accountIdFor('chequing');
    await accounts().put(
      id,
      accounts().get(id)!.copyWith(openingBalance: 900, label: 'Renamed'),
    );

    // Startup runs this every time, so the second run is the normal case,
    // not an edge one.
    await migrateCashHoldingsToAccounts();

    expect(accounts().get(id)!.openingBalance, 900);
    expect(accounts().get(id)!.label, 'Renamed');
    expect(accounts().length, 1);
  });

  test('sold and empty holdings do not become wallets', () async {
    await putCash(
      'closed',
      amount: 400,
      note: 'Closed',
      soldDate: DateTime(2026, 3, 1),
    );
    await putCash('empty', amount: 0, note: 'Empty');
    await putCash('real', amount: 120, note: 'Cash in hand');

    await migrateCashHoldingsToAccounts();

    expect(accounts().length, 1);
    expect(
      accounts().get(CashAccountMigrationPlanner.accountIdFor('real')),
      isNotNull,
    );
  });

  test('holdings that are not cash are ignored', () async {
    await assets().put(
      'gold',
      const Asset(id: 'gold', type: AssetType.gold, amount: 30, unit: 'g'),
    );

    await migrateCashHoldingsToAccounts();

    expect(accounts(), isEmpty);
  });

  test('an empty holdings box writes nothing', () async {
    await migrateCashHoldingsToAccounts();
    expect(accounts(), isEmpty);
  });

  test('every cash holding gets its own wallet', () async {
    await putCash('a', amount: 5000, note: 'Chequing');
    await putCash('b', amount: 200, note: 'Cash in hand');
    await putCash('c', amount: 3000, currency: 'CAD', note: 'Savings');

    await migrateCashHoldingsToAccounts();

    expect(accounts().length, 3);
    expect(
      accounts()
          .get(CashAccountMigrationPlanner.accountIdFor('c'))!
          .currency,
      'CAD',
    );
  });
}
