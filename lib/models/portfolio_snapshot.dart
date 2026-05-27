import 'package:hive/hive.dart';

part 'portfolio_snapshot.g.dart';

@HiveType(typeId: 7)
class PortfolioSnapshot {
  const PortfolioSnapshot({
    required this.id,
    required this.capturedAt,
    required this.totalUsd,
    required this.cashUsd,
    required this.bankSavingsUsd,
    required this.goldUsd,
    required this.silverUsd,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime capturedAt;

  @HiveField(2)
  final double totalUsd;

  @HiveField(3)
  final double cashUsd;

  @HiveField(4)
  final double bankSavingsUsd;

  @HiveField(5)
  final double goldUsd;

  @HiveField(6)
  final double silverUsd;
}
