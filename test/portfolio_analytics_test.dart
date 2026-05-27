import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/services/portfolio_analytics.dart';

void main() {
  test('groups active valued holdings by category', () {
    final analytics = PortfolioAnalytics.calculate([
      const Asset(id: 'cash', type: AssetType.cash, amount: 100, unit: 'USD'),
      const Asset(
        id: 'bank',
        type: AssetType.bankSavings,
        amount: 100,
        unit: 'EUR',
        currency: 'EUR',
      ),
      const Asset(
        id: 'gold',
        type: AssetType.gold,
        amount: 10,
        unit: 'g',
        purity: 50,
      ),
      Asset(
        id: 'sold-silver',
        type: AssetType.silver,
        amount: 100,
        unit: 'g',
        soldDate: DateTime(2026, 1, 1),
      ),
    ], _prices());

    expect(analytics.categoryValuesUsd[AssetType.cash], 100);
    expect(analytics.categoryValuesUsd[AssetType.bankSavings], 0);
    expect(analytics.categoryValuesUsd[AssetType.gold], 400);
    expect(analytics.totalUsd, 500);
    expect(analytics.activeAssetCount, 3);
    expect(analytics.soldAssetCount, 1);
    expect(analytics.unvaluedAssetCount, 1);
    expect(analytics.percentageFor(AssetType.gold), closeTo(400 / 500, 0.001));
  });

  test('tracks active assets that cannot yet be valued', () {
    final analytics = PortfolioAnalytics.calculate(const [
      Asset(
        id: 'unvalued-gold',
        type: AssetType.gold,
        amount: 5,
        unit: 'g',
        purity: 100,
      ),
    ], null);

    expect(analytics.totalUsd, 0);
    expect(analytics.unvaluedAssetCount, 1);
  });
}

MetalPriceSnapshot _prices() {
  return MetalPriceSnapshot(
    goldPerGramUsd: 80,
    silverPerGramUsd: 1,
    priceTimestamp: DateTime.utc(2026, 5, 27),
    fetchedAt: DateTime.utc(2026, 5, 27),
  );
}
