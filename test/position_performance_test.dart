import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/services/position_performance.dart';

void main() {
  test('compares active paid basis against current metal worth', () {
    final summary = PositionPerformance.calculate([
      const Asset(
        id: 'gold',
        type: AssetType.gold,
        amount: 5,
        unit: 'g',
        purity: 100,
        boughtPrice: 200,
      ),
      const Asset(id: 'cash', type: AssetType.cash, amount: 100, unit: 'USD'),
      Asset(
        id: 'sold-silver',
        type: AssetType.silver,
        amount: 20,
        unit: 'g',
        boughtPrice: 25,
        soldDate: DateTime(2026, 1, 1),
      ),
    ], _prices());

    expect(summary.paidUsd, 300);
    expect(summary.currentUsd, 375);
    expect(summary.changeUsd, 75);
    expect(summary.currentWorthFor(AssetType.gold), 275);
    expect(summary.paidFor(AssetType.cash), 100);
  });

  test('tracks AED cash in selected graph currency', () {
    final summary = PositionPerformance.calculate(
      const [
        Asset(
          id: 'aed',
          type: AssetType.cash,
          amount: 367.25,
          unit: 'AED',
          currency: 'AED',
        ),
      ],
      null,
      'AED',
    );

    expect(summary.currency, 'AED');
    expect(summary.currentWorthFor(AssetType.cash), 367.25);
    expect(summary.paidFor(AssetType.cash), 367.25);
    expect(summary.hasComparablePositions, isTrue);
  });
}

MetalPriceSnapshot _prices() {
  return MetalPriceSnapshot(
    goldPerGramUsd: 55,
    silverPerGramUsd: 1.1,
    priceTimestamp: DateTime.utc(2026, 5, 27),
    fetchedAt: DateTime.utc(2026, 5, 27),
  );
}
