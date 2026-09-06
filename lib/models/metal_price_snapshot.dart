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
    this.cadToUsd,
  });

  @HiveField(0)
  final double goldPerGramUsd;

  @HiveField(1)
  final double silverPerGramUsd;

  @HiveField(2)
  final DateTime priceTimestamp;

  @HiveField(3)
  final DateTime fetchedAt;

  /// USD per euro. Null on a snapshot taken before rates were fetched, or
  /// when the rate service could not be reached.
  @HiveField(4)
  final double? eurToUsd;

  /// USD per dirham. The peg makes this predictable, but a fetched rate is
  /// still preferred over the constant.
  @HiveField(5)
  final double? aedToUsd;

  /// USD per Canadian dollar.
  @HiveField(6)
  final double? cadToUsd;

  double? usdRateFor(String currency) {
    switch (currency.trim().toUpperCase()) {
      case 'USD':
        return 1;
      case 'EUR':
        return eurToUsd;
      case 'AED':
        return aedToUsd;
      case 'CAD':
        return cadToUsd;
      default:
        return null;
    }
  }
}
