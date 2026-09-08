import '../models/asset.dart';
import '../models/money_entry.dart';

/// What migrating a cash holding into an account would do.
class CashAccountMigration {
  const CashAccountMigration({
    required this.accounts,
    required this.migratedAssetIds,
    required this.skipped,
  });

  /// The accounts to write, one per cash holding.
  final List<MoneyAccount> accounts;

  /// The holdings those accounts replace.
  final List<String> migratedAssetIds;

  /// Holdings left alone, and why. Nothing is dropped silently.
  final Map<String, String> skipped;

  bool get isEmpty => accounts.isEmpty;
}

/// Works out how existing cash holdings become accounts.
///
/// Deliberately pure and not wired to anything yet: this rewrites holdings
/// somebody already owns, so the decisions want settling and reviewing before
/// a line of it runs. The zakat side of M4 executes it.
class CashAccountMigrationPlanner {
  const CashAccountMigrationPlanner();

  static const soldSkip = 'Sold holdings are history, not a balance';
  static const zeroSkip = 'Nothing to carry over';
  static const alreadyMigratedSkip = 'Already has an account';

  CashAccountMigration plan({
    required List<Asset> assets,
    required List<MoneyAccount> existingAccounts,
  }) {
    final existingIds = existingAccounts.map((account) => account.id).toSet();
    final accounts = <MoneyAccount>[];
    final migrated = <String>[];
    final skipped = <String, String>{};

    for (final asset in assets) {
      if (asset.type != AssetType.cash) continue;

      if (asset.isSold) {
        // A sold holding is a past event. Turning it into a balance would
        // resurrect money that is gone.
        skipped[asset.id] = soldSkip;
        continue;
      }
      if (asset.amount <= 0) {
        skipped[asset.id] = zeroSkip;
        continue;
      }

      final accountId = accountIdFor(asset.id);
      if (existingIds.contains(accountId)) {
        // Re-running must not produce a second account, or reset one whose
        // balance has since moved.
        skipped[asset.id] = alreadyMigratedSkip;
        continue;
      }

      accounts.add(
        MoneyAccount(
          id: accountId,
          label: asset.note?.trim().isNotEmpty ?? false
              ? asset.note!.trim()
              : 'Cash',
          currency: asset.currency,
          openingBalance: asset.amount,
          // The date the money was known to be there. Without one, entries
          // logged before the holding existed would be added on top of a
          // balance that already included them.
          openedOn: asset.boughtDate,
        ),
      );
      migrated.add(asset.id);
    }

    return CashAccountMigration(
      accounts: List.unmodifiable(accounts),
      migratedAssetIds: List.unmodifiable(migrated),
      skipped: Map.unmodifiable(skipped),
    );
  }

  /// Derived from the holding, so running the migration twice lands on the
  /// same account rather than making another.
  static String accountIdFor(String assetId) => 'cash:$assetId';
}
