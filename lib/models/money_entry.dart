import 'package:hive/hive.dart';

part 'money_entry.g.dart';

/// Which way the money went. Held on the entry rather than derived from its
/// category, so an entry saved without one still knows what it was.
@HiveType(typeId: 9)
enum MoneyDirection {
  @HiveField(0)
  income,
  @HiveField(1)
  expense,
}

extension MoneyDirectionDetails on MoneyDirection {
  String get label => this == MoneyDirection.income ? 'Income' : 'Expense';

  /// Income adds to a balance, expense takes away. Amounts are always stored
  /// positive so a sign error cannot quietly invert a total.
  int get sign => this == MoneyDirection.income ? 1 : -1;
}

@HiveType(typeId: 10)
class MoneyCategory {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String label;
  @HiveField(2)
  final MoneyDirection direction;

  /// Seeded categories can be hidden but not deleted, so an entry can never
  /// end up pointing at a category that no longer exists.
  @HiveField(3, defaultValue: false)
  final bool isBuiltIn;
  @HiveField(4, defaultValue: false)
  final bool isHidden;
  @HiveField(5, defaultValue: 0)
  final int sortIndex;

  const MoneyCategory({
    required this.id,
    required this.label,
    required this.direction,
    this.isBuiltIn = false,
    this.isHidden = false,
    this.sortIndex = 0,
  });

  MoneyCategory copyWith({
    String? label,
    MoneyDirection? direction,
    bool? isHidden,
    int? sortIndex,
  }) {
    return MoneyCategory(
      id: id,
      label: label ?? this.label,
      direction: direction ?? this.direction,
      isBuiltIn: isBuiltIn,
      isHidden: isHidden ?? this.isHidden,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }
}

/// Where money sits. Modelled from the start so entries never have to be
/// rewritten to gain an account, but only one exists until accounts are
/// surfaced — capture should not ask a question with a single answer.
@HiveType(typeId: 11)
class MoneyAccount {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String label;
  @HiveField(2, defaultValue: 'USD')
  final String currency;

  const MoneyAccount({
    required this.id,
    required this.label,
    this.currency = 'USD',
  });

  static const defaultId = 'default';

  MoneyAccount copyWith({String? label, String? currency}) {
    return MoneyAccount(
      id: id,
      label: label ?? this.label,
      currency: currency ?? this.currency,
    );
  }
}

/// One movement of money. Dated, signed by [direction], and never aggregated
/// into a stored balance — every total in the app is summed from these.
@HiveType(typeId: 12)
class MoneyEntry {
  @HiveField(0)
  final String id;

  /// Always positive. [direction] carries the sign.
  @HiveField(1)
  final double amount;
  @HiveField(2)
  final MoneyDirection direction;
  @HiveField(3, defaultValue: 'USD')
  final String currency;

  /// When the money moved, not when it was typed in. Zakat needs the former.
  @HiveField(4)
  final DateTime happenedAt;
  @HiveField(5, defaultValue: MoneyAccount.defaultId)
  final String accountId;
  @HiveField(6)
  final String? categoryId;
  @HiveField(7)
  final String? note;

  const MoneyEntry({
    required this.id,
    required this.amount,
    required this.direction,
    required this.happenedAt,
    this.currency = 'USD',
    this.accountId = MoneyAccount.defaultId,
    this.categoryId,
    this.note,
  });

  /// Positive for income, negative for expense.
  double get signedAmount => amount * direction.sign;

  bool get isIncome => direction == MoneyDirection.income;

  MoneyEntry copyWith({
    double? amount,
    MoneyDirection? direction,
    String? currency,
    DateTime? happenedAt,
    String? accountId,
    String? categoryId,
    bool clearCategory = false,
    String? note,
    bool clearNote = false,
  }) {
    return MoneyEntry(
      id: id,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      currency: currency ?? this.currency,
      happenedAt: happenedAt ?? this.happenedAt,
      accountId: accountId ?? this.accountId,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      note: clearNote ? null : note ?? this.note,
    );
  }
}
