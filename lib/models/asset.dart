import 'package:hive/hive.dart';

part 'asset.g.dart';

@HiveType(typeId: 0)
enum AssetType {
  @HiveField(0)
  cash,
  @HiveField(1)
  bankSavings,
  @HiveField(2)
  gold,
  @HiveField(3)
  silver,
}

extension AssetTypeDetails on AssetType {
  bool get isMetal => this == AssetType.gold || this == AssetType.silver;

  String get label {
    switch (this) {
      case AssetType.cash:
        return 'Cash';
      case AssetType.bankSavings:
        return 'Bank Savings';
      case AssetType.gold:
        return 'Gold';
      case AssetType.silver:
        return 'Silver';
    }
  }
}

@HiveType(typeId: 8)
enum AssetTag {
  @HiveField(0)
  freelance,
  @HiveField(1)
  emergency,
  @HiveField(2)
  gift,
  @HiveField(3)
  salary,
  @HiveField(4)
  businessProfit,
}

extension AssetTagDetails on AssetTag {
  String get label {
    switch (this) {
      case AssetTag.freelance:
        return 'Freelance';
      case AssetTag.emergency:
        return 'Emergency';
      case AssetTag.gift:
        return 'Gift';
      case AssetTag.salary:
        return 'Salary';
      case AssetTag.businessProfit:
        return 'Business Profit';
    }
  }
}

@HiveType(typeId: 1)
class Asset {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final AssetType type;
  @HiveField(2)
  final double amount;
  @HiveField(3)
  final String unit;
  @HiveField(4)
  final double? purity;
  @HiveField(5)
  final DateTime? boughtDate;
  @HiveField(6)
  final double? boughtPrice;
  @HiveField(7)
  final DateTime? soldDate;
  @HiveField(8)
  final double? soldPrice;
  @HiveField(9)
  final String? note;
  @HiveField(10, defaultValue: 'USD')
  final String currency;
  @HiveField(11)
  final AssetTag? tag;

  const Asset({
    required this.id,
    required this.type,
    required this.amount,
    required this.unit,

    this.purity,
    this.boughtDate,
    this.boughtPrice,
    this.soldDate,
    this.soldPrice,
    this.note,
    this.currency = 'USD',
    this.tag,
  });

  bool get isSold => soldDate != null;
}
