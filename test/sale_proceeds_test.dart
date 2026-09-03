import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/main.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/services/wealth_calculator.dart';
import 'package:moniz/services/zakat_engine.dart';

/// 20g of gold bought two years ago, sold today for what it is worth.
final _sold = Asset(
  id: 'gold',
  type: AssetType.gold,
  amount: 20,
  unit: 'g',
  purity: 100,
  currency: 'USD',
  tag: AssetTag.salary,
  boughtDate: DateTime(2024, 1, 1),
  soldDate: DateTime(2026, 9, 3),
  soldPrice: 2000,
);

MetalPriceSnapshot _prices() {
  return MetalPriceSnapshot(
    goldPerGramUsd: 100,
    silverPerGramUsd: 1,
    priceTimestamp: DateTime.utc(2026, 9, 3),
    fetchedAt: DateTime.utc(2026, 9, 3),
  );
}

void main() {
  test('proceeds carry the amount, currency and tag of the sale', () {
    final cash = buildSaleProceeds(_sold, 'proceeds');

    expect(cash.type, AssetType.cash);
    expect(cash.amount, 2000);
    expect(cash.currency, 'USD');
    expect(cash.unit, 'USD');
    expect(cash.tag, AssetTag.salary);
    expect(cash.note, contains('Proceeds from selling 20 g'));
    expect(cash.isSold, isFalse);
  });

  test('the lunar year continues across the sale', () {
    final cash = buildSaleProceeds(_sold, 'proceeds');

    // Not the sale date: restarting here would let someone sell just before
    // an anniversary and owe nothing on that wealth for another year.
    expect(cash.boughtDate, DateTime(2024, 1, 1));
  });

  test('recording proceeds keeps wealth whole across a sale', () {
    final held = Asset(
      id: 'gold',
      type: AssetType.gold,
      amount: 20,
      unit: 'g',
      purity: 100,
      boughtDate: DateTime(2024, 1, 1),
    );

    final before = WealthCalculator.calculateUsd([held], _prices());
    final afterWithout = WealthCalculator.calculateUsd([_sold], _prices());
    final afterWith = WealthCalculator.calculateUsd([
      _sold,
      buildSaleProceeds(_sold, 'proceeds'),
    ], _prices());

    expect(before.totalUsd, 2000);
    expect(afterWithout.totalUsd, 0); // the money used to just disappear
    expect(afterWith.totalUsd, 2000);
  });

  test('and keeps the zakat owed on that wealth', () {
    ZakatResult zakat(List<Asset> assets) => ZakatEngine.calculate(
      assets: assets,
      prices: _prices(),
      settings: const ZakatSettings(
        scheduleMode: ZakatScheduleMode.individualDueDates,
      ),
      payments: const {},
      today: DateTime(2026, 9, 4),
    );

    expect(zakat([_sold]).amountDueUsd, 0);
    expect(
      zakat([_sold, buildSaleProceeds(_sold, 'proceeds')]).amountDueUsd,
      50,
    );
  });
}
