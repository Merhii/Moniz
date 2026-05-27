import '../models/asset.dart';
import '../models/metal_price_snapshot.dart';
import 'wealth_calculator.dart';

class PortfolioAnalytics {
  const PortfolioAnalytics({
    required this.categoryValuesUsd,
    required this.totalUsd,
    required this.activeAssetCount,
    required this.soldAssetCount,
    required this.unvaluedAssetCount,
  });

  final Map<AssetType, double> categoryValuesUsd;
  final double totalUsd;
  final int activeAssetCount;
  final int soldAssetCount;
  final int unvaluedAssetCount;

  double percentageFor(AssetType type) {
    if (totalUsd == 0) return 0;
    return (categoryValuesUsd[type] ?? 0) / totalUsd;
  }

  static PortfolioAnalytics calculate(
    List<Asset> assets,
    MetalPriceSnapshot? prices,
  ) {
    final categoryValues = {for (final type in AssetType.values) type: 0.0};
    var activeCount = 0;
    var soldCount = 0;
    var unvaluedCount = 0;

    for (final asset in assets) {
      if (asset.isSold) {
        soldCount += 1;
        continue;
      }
      activeCount += 1;
      final valueUsd = WealthCalculator.valueAssetUsd(asset, prices);
      if (valueUsd == null) {
        unvaluedCount += 1;
        continue;
      }
      categoryValues[asset.type] = categoryValues[asset.type]! + valueUsd;
    }

    return PortfolioAnalytics(
      categoryValuesUsd: categoryValues,
      totalUsd: categoryValues.values.fold(0, (sum, value) => sum + value),
      activeAssetCount: activeCount,
      soldAssetCount: soldCount,
      unvaluedAssetCount: unvaluedCount,
    );
  }
}
