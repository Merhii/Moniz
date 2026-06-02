import '../models/asset.dart';
import '../models/metal_price_snapshot.dart';
import 'currency_converter.dart';
import 'wealth_calculator.dart';

class PositionPerformanceSummary {
  const PositionPerformanceSummary({
    required this.paidUsd,
    required this.currentUsd,
    required this.currentWorthByTypeUsd,
    required this.paidByTypeUsd,
    required this.currentByTypeUsd,
    required this.comparableAssetCount,
    required this.missingBoughtPriceCount,
    required this.unpricedAssetCount,
    required this.unsupportedCurrencyCount,
    this.currency = CurrencyConverter.defaultCurrency,
  });

  final double paidUsd;
  final double currentUsd;
  final Map<AssetType, double> currentWorthByTypeUsd;
  final Map<AssetType, double> paidByTypeUsd;
  final Map<AssetType, double> currentByTypeUsd;
  final int comparableAssetCount;
  final int missingBoughtPriceCount;
  final int unpricedAssetCount;
  final int unsupportedCurrencyCount;
  final String currency;

  double get changeUsd => currentUsd - paidUsd;

  bool get hasComparablePositions => comparableAssetCount > 0;

  bool get hasTrackedCurrentWorth =>
      currentWorthByTypeUsd.values.any((value) => value > 0);

  double currentWorthFor(AssetType type) => currentWorthByTypeUsd[type] ?? 0;

  double paidFor(AssetType type) => paidByTypeUsd[type] ?? 0;

  double comparableCurrentFor(AssetType type) => currentByTypeUsd[type] ?? 0;
}

class PositionPerformance {
  static const trackedTypes = [
    AssetType.cash,
    AssetType.gold,
    AssetType.silver,
  ];

  static PositionPerformanceSummary calculate(
    List<Asset> assets,
    MetalPriceSnapshot? prices,
    String displayCurrency = CurrencyConverter.defaultCurrency,
  ) {
    final normalizedDisplayCurrency = CurrencyConverter.normalize(
      displayCurrency,
    );
    final currentWorthByType = _emptyTrackedMap();
    final paidByType = _emptyTrackedMap();
    final currentByType = _emptyTrackedMap();
    var paidUsd = 0.0;
    var currentUsd = 0.0;
    var comparableAssetCount = 0;
    var missingBoughtPriceCount = 0;
    var unpricedAssetCount = 0;
    var unsupportedCurrencyCount = 0;

    for (final asset in assets.where((asset) => !asset.isSold)) {
      final trackedType = _trackedTypeFor(asset.type);

      final currentWorth = WealthCalculator.valueAsset(
        asset,
        prices,
        displayCurrency: normalizedDisplayCurrency,
      );
      if (currentWorth == null) {
        if (asset.type.isMetal) {
          unpricedAssetCount += 1;
        } else {
          unsupportedCurrencyCount += 1;
        }
        continue;
      }
      currentWorthByType[trackedType] =
          currentWorthByType[trackedType]! + currentWorth;

      final paidValue = _paidValue(
        asset,
        currentWorth,
        prices,
        normalizedDisplayCurrency,
      );
      if (paidValue == null) {
        if (asset.type.isMetal && asset.boughtPrice == null) {
          missingBoughtPriceCount += 1;
        } else {
          unsupportedCurrencyCount += 1;
        }
        continue;
      }

      paidByType[trackedType] = paidByType[trackedType]! + paidValue;
      currentByType[trackedType] = currentByType[trackedType]! + currentWorth;
      paidUsd += paidValue;
      currentUsd += currentWorth;
      comparableAssetCount += 1;
    }

    return PositionPerformanceSummary(
      paidUsd: paidUsd,
      currentUsd: currentUsd,
      currentWorthByTypeUsd: currentWorthByType,
      paidByTypeUsd: paidByType,
      currentByTypeUsd: currentByType,
      comparableAssetCount: comparableAssetCount,
      missingBoughtPriceCount: missingBoughtPriceCount,
      unpricedAssetCount: unpricedAssetCount,
      unsupportedCurrencyCount: unsupportedCurrencyCount,
      currency: normalizedDisplayCurrency,
    );
  }

  static Map<AssetType, double> _emptyTrackedMap() {
    return {for (final type in trackedTypes) type: 0.0};
  }

  static AssetType _trackedTypeFor(AssetType type) {
    switch (type) {
      case AssetType.cash:
      case AssetType.bankSavings:
        return AssetType.cash;
      case AssetType.gold:
        return AssetType.gold;
      case AssetType.silver:
        return AssetType.silver;
    }
  }

  static double? _paidValue(
    Asset asset,
    double currentWorth,
    MetalPriceSnapshot? prices,
    String displayCurrency,
  ) {
    if (!asset.type.isMetal) {
      return currentWorth;
    }
    final boughtPrice = asset.boughtPrice;
    if (boughtPrice == null) return null;
    return CurrencyConverter.convert(
      boughtPrice,
      from: asset.currency,
      to: displayCurrency,
      prices: prices,
    );
  }
}
