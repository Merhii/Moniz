import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/services/wealth_calculator.dart';

void main() {
  test('calculates active USD assets and purity adjusted metal values', () {
    final totals = WealthCalculator.calculateUsd(
      [
        const Asset(id: 'cash', type: AssetType.cash, amount: 100, unit: 'USD'),
        const Asset(
          id: 'gold',
          type: AssetType.gold,
          amount: 10,
          unit: 'g',
          purity: 75,
        ),
        Asset(
          id: 'sold-silver',
          type: AssetType.silver,
          amount: 50,
          unit: 'g',
          purity: 100,
          soldDate: DateTime(2026, 1, 1),
        ),
        const Asset(
          id: 'eur',
          type: AssetType.bankSavings,
          amount: 100,
          unit: 'EUR',
          currency: 'EUR',
        ),
        const Asset(
          id: 'aed',
          type: AssetType.cash,
          amount: 367.25,
          unit: 'AED',
          currency: 'AED',
        ),
      ],
      MetalPriceSnapshot(
        goldPerGramUsd: 80,
        silverPerGramUsd: 1,
        priceTimestamp: DateTime.utc(2026, 5, 27),
        fetchedAt: DateTime.utc(2026, 5, 27),
      ),
    );

    expect(totals.totalUsd, closeTo(700, 0.01));
    expect(totals.hasUnsupportedCurrencies, isTrue);
    expect(totals.hasUnpricedMetals, isFalse);
  });

  test('flags non-USD monetary holdings without an FX provider', () {
    final totals = WealthCalculator.calculateUsd(const [
      Asset(
        id: 'eur',
        type: AssetType.cash,
        amount: 50,
        unit: 'EUR',
        currency: 'EUR',
      ),
      Asset(
        id: 'gold',
        type: AssetType.gold,
        amount: 5,
        unit: 'g',
        purity: 99.9,
      ),
    ], null);

    expect(totals.totalUsd, 0);
    expect(totals.hasUnsupportedCurrencies, isTrue);
    expect(totals.hasUnpricedMetals, isTrue);
  });

  test('flags other monetary currencies without an FX provider', () {
    final totals = WealthCalculator.calculateUsd(
      const [
        Asset(
          id: 'sar',
          type: AssetType.cash,
          amount: 50,
          unit: 'SAR',
          currency: 'SAR',
        ),
      ],
      MetalPriceSnapshot(
        goldPerGramUsd: 80,
        silverPerGramUsd: 1,
        priceTimestamp: DateTime.utc(2026, 5, 27),
        fetchedAt: DateTime.utc(2026, 5, 27),
      ),
    );

    expect(totals.totalUsd, 0);
    expect(totals.hasUnsupportedCurrencies, isTrue);
  });
}
