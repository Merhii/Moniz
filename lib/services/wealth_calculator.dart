import '../models/asset.dart';
import '../models/metal_price_snapshot.dart';
import 'currency_converter.dart';

class WealthTotals {
  const WealthTotals({
    required this.totalValue,
    required this.currency,
    required this.hasUnsupportedCurrencies,
    required this.hasUnpricedMetals,
  });

  final double totalValue;
  final String currency;
  final bool hasUnsupportedCurrencies;
  final bool hasUnpricedMetals;

  double get totalUsd => totalValue;
}

class WealthCalculator {
  static double? valueAsset(
    Asset asset,
    MetalPriceSnapshot? prices, {
    String displayCurrency = CurrencyConverter.defaultCurrency,
  }) {
    final normalizedDisplayCurrency = CurrencyConverter.normalize(
      displayCurrency,
    );
    if (!asset.type.isMetal) {
      return CurrencyConverter.convert(
        asset.amount,
        from: asset.currency,
        to: normalizedDisplayCurrency,
        prices: prices,
      );
    }

    if (prices == null) return null;
    final purityFactor = (asset.purity ?? 100) / 100;
    final pricePerGram = asset.type == AssetType.gold
        ? prices.goldPerGramUsd
        : prices.silverPerGramUsd;
    final valueUsd = asset.amount * purityFactor * pricePerGram;
    return CurrencyConverter.convertFromUsd(
      valueUsd,
      normalizedDisplayCurrency,
      prices: prices,
    );
  }

  static double? valueAssetUsd(Asset asset, MetalPriceSnapshot? prices) {
    return valueAsset(
      asset,
      prices,
      displayCurrency: CurrencyConverter.defaultCurrency,
    );
  }

  static WealthTotals calculate(
    List<Asset> assets,
    MetalPriceSnapshot? prices,
    String displayCurrency,
  ) {
    final normalizedDisplayCurrency = CurrencyConverter.normalize(
      displayCurrency,
    );
    var totalValue = 0.0;
    var hasUnsupportedCurrencies = false;
    var hasUnpricedMetals = false;

    for (final asset in assets.where((asset) => !asset.isSold)) {
      final value = valueAsset(
        asset,
        prices,
        displayCurrency: normalizedDisplayCurrency,
      );
      if (value != null) {
        totalValue += value;
      } else if (asset.type.isMetal) {
        hasUnpricedMetals = true;
      } else {
        hasUnsupportedCurrencies = true;
      }
    }

    return WealthTotals(
      totalValue: totalValue,
      currency: normalizedDisplayCurrency,
      hasUnsupportedCurrencies: hasUnsupportedCurrencies,
      hasUnpricedMetals: hasUnpricedMetals,
    );
  }

  static WealthTotals calculateUsd(
    List<Asset> assets,
    MetalPriceSnapshot? prices,
  ) {
    return calculate(assets, prices, CurrencyConverter.defaultCurrency);
  }
}
