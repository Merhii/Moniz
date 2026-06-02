import '../models/asset.dart';
import '../models/metal_price_snapshot.dart';
import 'currency_converter.dart';
import 'wealth_calculator.dart';

class PortfolioAnalytics {
  const PortfolioAnalytics({
    required this.categoryValuesUsd,
    required this.totalUsd,
    required this.activeAssetCount,
    required this.soldAssetCount,
    required this.unvaluedAssetCount,
    this.currency = CurrencyConverter.defaultCurrency,
  });

  final Map<AssetType, double> categoryValuesUsd;
  final double totalUsd;
  final int activeAssetCount;
  final int soldAssetCount;
  final int unvaluedAssetCount;
  final String currency;

  double percentageFor(AssetType type) {
    if (totalUsd == 0) return 0;
    return (categoryValuesUsd[type] ?? 0) / totalUsd;
  }

  static PortfolioAnalytics calculate(
    List<Asset> assets,
    MetalPriceSnapshot? prices,
    String displayCurrency = CurrencyConverter.defaultCurrency,
  ) {
    final normalizedDisplayCurrency = CurrencyConverter.normalize(
      displayCurrency,
    );
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
      final value = WealthCalculator.valueAsset(
        asset,
        prices,
        displayCurrency: normalizedDisplayCurrency,
      );
      if (value == null) {
        unvaluedCount += 1;
        continue;
      }
      categoryValues[asset.type] = categoryValues[asset.type]! + value;
    }

    return PortfolioAnalytics(
      categoryValuesUsd: categoryValues,
      totalUsd: categoryValues.values.fold(0, (sum, value) => sum + value),
      activeAssetCount: activeCount,
      soldAssetCount: soldCount,
      unvaluedAssetCount: unvaluedCount,
      currency: normalizedDisplayCurrency,
    );
  }

  static PortfolioAnalytics calculateUsd(
    List<Asset> assets,
    MetalPriceSnapshot? prices,
  ) {
    return calculate(assets, prices, CurrencyConverter.defaultCurrency);
  }
}
