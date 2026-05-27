import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/services/dashboard_filter.dart';

void main() {
  const assets = [
    Asset(
      id: 'salary-cash',
      type: AssetType.cash,
      amount: 1000,
      unit: 'USD',
      tag: AssetTag.salary,
    ),
    Asset(
      id: 'gift-gold',
      type: AssetType.gold,
      amount: 10,
      unit: 'g',
      tag: AssetTag.gift,
    ),
  ];

  test('filters assets by type and tag', () {
    const filter = DashboardFilter(type: AssetType.gold, tag: AssetTag.gift);

    expect(filter.apply(assets).single.id, 'gift-gold');
  });

  test('date range includes acquisition or sale activity', () {
    final datedAssets = [
      Asset(
        id: 'gold',
        type: AssetType.gold,
        amount: 10,
        unit: 'g',
        boughtDate: DateTime(2025, 1, 1),
        soldDate: DateTime(2026, 4, 10),
      ),
      Asset(
        id: 'cash-without-date',
        type: AssetType.cash,
        amount: 20,
        unit: 'USD',
      ),
    ];
    final filter = DashboardFilter(
      fromDate: DateTime(2026, 4, 1),
      toDate: DateTime(2026, 4, 30),
    );

    expect(filter.apply(datedAssets).single.id, 'gold');
  });
}
