import '../models/asset.dart';
import '../models/metal_price_snapshot.dart';

class WealthTotals {
  const WealthTotals({
    required this.totalUsd,
    required this.hasUnsupportedCurrencies,
    required this.hasUnpricedMetals,
  });

  final double totalUsd;
  final bool hasUnsupportedCurrencies;
  final bool hasUnpricedMetals;
}

class WealthCalculator {
  static double? valueAssetUsd(Asset asset, MetalPriceSnapshot? prices) {
    if (!asset.type.isMetal) {
      final exchangeRate = asset.currency == 'USD'
          ? 1.0
          : prices?.usdRateFor(asset.currency);
      return exchangeRate == null ? null : asset.amount * exchangeRate;
    }

    if (prices == null) return null;
    final purityFactor = (asset.purity ?? 100) / 100;
    final pricePerGram = asset.type == AssetType.gold
        ? prices.goldPerGramUsd
        : prices.silverPerGramUsd;
    return asset.amount * purityFactor * pricePerGram;
  }

  static WealthTotals calculateUsd(
    List<Asset> assets,
    MetalPriceSnapshot? prices,
  ) {
    var totalUsd = 0.0;
    var hasUnsupportedCurrencies = false;
    var hasUnpricedMetals = false;

    for (final asset in assets.where((asset) => !asset.isSold)) {
      final valueUsd = valueAssetUsd(asset, prices);
      if (valueUsd != null) {
        totalUsd += valueUsd;
      } else if (asset.type.isMetal) {
        hasUnpricedMetals = true;
      } else {
        hasUnsupportedCurrencies = true;
      }
    }

    return WealthTotals(
      totalUsd: totalUsd,
      hasUnsupportedCurrencies: hasUnsupportedCurrencies,
      hasUnpricedMetals: hasUnpricedMetals,
    );
  }
}
