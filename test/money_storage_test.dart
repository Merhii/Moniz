import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/providers/money_entry_provider.dart';
import 'package:moniz/services/money_category_catalog.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_money_');
    Hive.init(hiveDirectory.path);
    registerMonizAdapters();
    await Hive.openBox<MoneyEntry>('moneyEntries');
    await Hive.openBox<MoneyCategory>('moneyCategories');
    await Hive.openBox<MoneyAccount>('moneyAccounts');
  });

  setUp(() async {
    await Hive.box<MoneyEntry>('moneyEntries').clear();
    await Hive.box<MoneyCategory>('moneyCategories').clear();
    await Hive.box<MoneyAccount>('moneyAccounts').clear();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('an entry survives a round trip through the box', () async {
    final notifier = MoneyEntryNotifier(
      entryBox: Hive.box<MoneyEntry>('moneyEntries'),
    );
    await notifier.addEntry(
      MoneyEntry(
        id: 'coffee',
        amount: 3.5,
        direction: MoneyDirection.expense,
        happenedAt: DateTime(2026, 9, 6, 8, 30),
        categoryId: 'expense.eatingout',
      ),
    );

    final reopened = MoneyEntryNotifier(
      entryBox: Hive.box<MoneyEntry>('moneyEntries'),
    );
    final entry = reopened.state.single;
    expect(entry.amount, 3.5);
    expect(entry.direction, MoneyDirection.expense);
    expect(entry.happenedAt, DateTime(2026, 9, 6, 8, 30));
    expect(entry.categoryId, 'expense.eatingout');
    expect(entry.accountId, MoneyAccount.defaultId);
    expect(entry.currency, 'USD');
  });

  test('editing replaces rather than duplicating', () async {
    final notifier = MoneyEntryNotifier(
      entryBox: Hive.box<MoneyEntry>('moneyEntries'),
    );
    final entry = MoneyEntry(
      id: 'lunch',
      amount: 12,
      direction: MoneyDirection.expense,
      happenedAt: DateTime(2026, 9, 6),
    );
    await notifier.addEntry(entry);
    await notifier.updateEntry(entry.copyWith(amount: 14));

    expect(notifier.state, hasLength(1));
    expect(notifier.state.single.amount, 14);

    await notifier.removeEntry('lunch');
    expect(notifier.state, isEmpty);
  });

  test('seeding fills an empty box and is safe to run again', () async {
    final categories = Hive.box<MoneyCategory>('moneyCategories');
    await seedMoneyDefaults();
    final afterFirst = categories.length;

    expect(afterFirst, MoneyCategoryCatalog.seeded.length);
    expect(
      Hive.box<MoneyAccount>('moneyAccounts').get(MoneyAccount.defaultId),
      isNotNull,
    );

    await seedMoneyDefaults();
    expect(categories.length, afterFirst, reason: 'no duplicates on restart');
  });

  test('seeding does not undo a rename or a hide', () async {
    final categories = Hive.box<MoneyCategory>('moneyCategories');
    await seedMoneyDefaults();

    final groceries = categories.get('expense.groceries')!;
    await categories.put(
      'expense.groceries',
      groceries.copyWith(label: 'Food shop', isHidden: true),
    );

    // Startup seeding runs on every launch, so it must never overwrite an
    // edit the owner made.
    await seedMoneyDefaults();
    final after = categories.get('expense.groceries')!;
    expect(after.label, 'Food shop');
    expect(after.isHidden, isTrue);
  });

  test('a new release can add a category without a migration', () async {
    final categories = Hive.box<MoneyCategory>('moneyCategories');
    await seedMoneyDefaults();
    await categories.delete('expense.charity');
    expect(categories.length, MoneyCategoryCatalog.seeded.length - 1);

    await seedMoneyDefaults();
    expect(categories.get('expense.charity'), isNotNull);
  });

  test('a built-in category hides, a custom one deletes', () async {
    final box = Hive.box<MoneyCategory>('moneyCategories');
    final notifier = MoneyCategoryNotifier(categoryBox: box);
    await seedMoneyDefaults();
    notifier.loadCategories();
    await notifier.upsert(
      const MoneyCategory(
        id: 'custom.coffee',
        label: 'Coffee',
        direction: MoneyDirection.expense,
      ),
    );

    await notifier.remove('expense.rent');
    await notifier.remove('custom.coffee');

    // Hiding keeps entries filed against it pointing at something real.
    expect(box.get('expense.rent')!.isHidden, isTrue);
    expect(box.get('custom.coffee'), isNull);
  });

  test('the money boxes are opened with the same cipher as the rest', () {
    // Spending is at least as sensitive as holdings; a plaintext box sitting
    // beside the encrypted ones would be the weakest link.
    expect(monizBoxNames, containsAll(<String>['assets', 'uiPreferences']));
    expect(
      monizBoxNames,
      containsAll(<String>['moneyEntries', 'moneyCategories', 'moneyAccounts']),
    );
  });
}
