import 'package:hive/hive.dart';

part 'metal_price_snapshot.g.dart';

@HiveType(typeId: 2)
class MetalPriceSnapshot {
  const MetalPriceSnapshot({
    required this.goldPerGramUsd,
    required this.silverPerGramUsd,
    required this.priceTimestamp,
    required this.fetchedAt,
    this.eurToUsd,
    this.aedToUsd,
  });

  @HiveField(0)
  final double goldPerGramUsd;

  @HiveField(1)
  final double silverPerGramUsd;

  @HiveField(2)
  final DateTime priceTimestamp;

  @HiveField(3)
  final DateTime fetchedAt;

  @HiveField(4)
  // Retained to deserialize snapshots created by the previous price provider.
  final double? eurToUsd;

  @HiveField(5)
  // Retained to deserialize snapshots created by the previous price provider.
  final double? aedToUsd;

  double? usdRateFor(String currency) {
    switch (currency.trim().toUpperCase()) {
      case 'USD':
        return 1;
      case 'EUR':
        return eurToUsd;
      case 'AED':
        return aedToUsd;
      default:
        return null;
    }
  }
}
