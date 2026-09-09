import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/money_entry.dart';
import '../services/launch_action_service.dart';
import '../services/money_category_catalog.dart';

class MoneyEntryNotifier extends StateNotifier<List<MoneyEntry>> {
  MoneyEntryNotifier({Box<MoneyEntry>? entryBox})
    : entryBox = entryBox ?? Hive.box<MoneyEntry>('moneyEntries'),
      super(
        (entryBox ?? Hive.box<MoneyEntry>('moneyEntries')).values.toList(),
      );

  final Box<MoneyEntry> entryBox;

  void loadEntries() {
    state = entryBox.values.toList();
  }

  Future<void> addEntry(MoneyEntry entry) async {
    await entryBox.put(entry.id, entry);
    loadEntries();
  }

  Future<void> updateEntry(MoneyEntry entry) async {
    await entryBox.put(entry.id, entry);
    loadEntries();
  }

  Future<void> removeEntry(String id) async {
    await entryBox.delete(id);
    loadEntries();
  }
}

class MoneyCategoryNotifier extends StateNotifier<List<MoneyCategory>> {
  MoneyCategoryNotifier({Box<MoneyCategory>? categoryBox})
    : categoryBox = categoryBox ?? Hive.box<MoneyCategory>('moneyCategories'),
      super(
        _sorted(
          (categoryBox ?? Hive.box<MoneyCategory>('moneyCategories')).values,
        ),
      );

  final Box<MoneyCategory> categoryBox;

  void loadCategories() {
    state = _sorted(categoryBox.values);
  }

  /// Writes any seeded category the box is missing. Runs on every start so a
  /// later release can add one without a migration, and leaves renames and
  /// hidden flags on the ones already stored untouched.
  Future<void> seedMissing() async {
    final missing = MoneyCategoryCatalog.missingFrom(categoryBox.keys.cast());
    if (missing.isEmpty) return;
    await categoryBox.putAll({
      for (final category in missing) category.id: category,
    });
    loadCategories();
  }

  Future<void> upsert(MoneyCategory category) async {
    await categoryBox.put(category.id, category);
    loadCategories();
  }

  /// Built-in categories are hidden rather than removed, so entries filed
  /// against them keep pointing at something that exists.
  Future<void> remove(String id) async {
    final existing = categoryBox.get(id);
    if (existing == null) return;
    if (existing.isBuiltIn) {
      await categoryBox.put(id, existing.copyWith(isHidden: true));
    } else {
      await categoryBox.delete(id);
    }
    loadCategories();
  }

  static List<MoneyCategory> _sorted(Iterable<MoneyCategory> categories) {
    final list = categories.toList()
      ..sort((a, b) {
        final byDirection = a.direction.index.compareTo(b.direction.index);
        if (byDirection != 0) return byDirection;
        final byOrder = a.sortIndex.compareTo(b.sortIndex);
        return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
      });
    return List.unmodifiable(list);
  }
}

final moneyEntryProvider =
    StateNotifierProvider<MoneyEntryNotifier, List<MoneyEntry>>(
      (ref) => MoneyEntryNotifier(),
    );

final moneyCategoryProvider =
    StateNotifierProvider<MoneyCategoryNotifier, List<MoneyCategory>>(
      (ref) => MoneyCategoryNotifier(),
    );

/// Only the categories worth offering in the picker.
final visibleMoneyCategoriesProvider = Provider<List<MoneyCategory>>((ref) {
  return List.unmodifiable(
    ref.watch(moneyCategoryProvider).where((category) => !category.isHidden),
  );
});

final launchActionReaderProvider = Provider<LaunchActionReader>(
  (ref) => const PlatformLaunchActionReader(),
);

class MoneyAccountNotifier extends StateNotifier<List<MoneyAccount>> {
  MoneyAccountNotifier({Box<MoneyAccount>? accountBox})
    : accountBox = accountBox ?? Hive.box<MoneyAccount>('moneyAccounts'),
      super(
        (accountBox ?? Hive.box<MoneyAccount>('moneyAccounts')).values.toList(),
      );

  final Box<MoneyAccount> accountBox;

  void loadAccounts() {
    state = accountBox.values.toList();
  }

  Future<void> upsert(MoneyAccount account) async {
    await accountBox.put(account.id, account);
    loadAccounts();
  }

  Future<void> setOpeningBalance(
    String id, {
    required double openingBalance,
    DateTime? openedOn,
  }) async {
    final existing = accountBox.get(id);
    if (existing == null) return;
    await accountBox.put(
      id,
      existing.copyWith(openingBalance: openingBalance, openedOn: openedOn),
    );
    loadAccounts();
  }
}

final moneyAccountProvider =
    StateNotifierProvider<MoneyAccountNotifier, List<MoneyAccount>>(
      (ref) => MoneyAccountNotifier(),
    );

/// Accounts in a stable order, so a picker built from them does not reshuffle
/// as Hive hands them back. The wallet somebody started with leads, then the
/// rest by label.
final spendableAccountsProvider = Provider<List<MoneyAccount>>((ref) {
  final accounts = ref.watch(moneyAccountProvider).toList()
    ..sort((a, b) {
      if (a.id == b.id) return 0;
      if (a.id == MoneyAccount.defaultId) return -1;
      if (b.id == MoneyAccount.defaultId) return 1;
      final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
      return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
    });
  return List.unmodifiable(accounts);
});

/// The wallet somebody started with.
final defaultAccountProvider = Provider<MoneyAccount?>((ref) {
  final accounts = ref.watch(moneyAccountProvider);
  for (final account in accounts) {
    if (account.id == MoneyAccount.defaultId) return account;
  }
  return null;
});
