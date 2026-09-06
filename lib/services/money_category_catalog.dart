import '../models/money_entry.dart';

/// The categories a new install starts with.
///
/// The income side is lifted from the tags the app already ships on holdings
/// (`AssetTag.salary`, `.freelance`, `.businessProfit`, `.gift`) so the two
/// vocabularies agree instead of drifting apart.
///
/// The expense side is deliberately short. A long list slows down the one tap
/// that has to stay fast, and unused categories are harder to remove than
/// missing ones are to add.
class MoneyCategoryCatalog {
  const MoneyCategoryCatalog();

  static const seeded = <MoneyCategory>[
    // Income
    MoneyCategory(id: 'income.salary', label: 'Salary', direction: MoneyDirection.income, isBuiltIn: true, sortIndex: 0),
    MoneyCategory(id: 'income.freelance', label: 'Freelance', direction: MoneyDirection.income, isBuiltIn: true, sortIndex: 1),
    MoneyCategory(id: 'income.business', label: 'Business profit', direction: MoneyDirection.income, isBuiltIn: true, sortIndex: 2),
    MoneyCategory(id: 'income.gift', label: 'Gift', direction: MoneyDirection.income, isBuiltIn: true, sortIndex: 3),
    MoneyCategory(id: 'income.other', label: 'Other income', direction: MoneyDirection.income, isBuiltIn: true, sortIndex: 4),

    // Expense
    MoneyCategory(id: 'expense.groceries', label: 'Groceries', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 0),
    MoneyCategory(id: 'expense.eatingout', label: 'Eating out', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 1),
    MoneyCategory(id: 'expense.transport', label: 'Transport', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 2),
    MoneyCategory(id: 'expense.rent', label: 'Rent', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 3),
    MoneyCategory(id: 'expense.bills', label: 'Bills', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 4),
    MoneyCategory(id: 'expense.shopping', label: 'Shopping', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 5),
    MoneyCategory(id: 'expense.health', label: 'Health', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 6),
    MoneyCategory(id: 'expense.charity', label: 'Charity', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 7),
    MoneyCategory(id: 'expense.other', label: 'Other', direction: MoneyDirection.expense, isBuiltIn: true, sortIndex: 8),
  ];

  static const defaultAccount = MoneyAccount(
    id: MoneyAccount.defaultId,
    label: 'Wallet',
  );

  /// Adds any seeded category the box has not seen, without disturbing edits
  /// or hidden flags already stored against the ones it has.
  static List<MoneyCategory> missingFrom(Iterable<String> existingIds) {
    final existing = existingIds.toSet();
    return seeded
        .where((category) => !existing.contains(category.id))
        .toList(growable: false);
  }
}
