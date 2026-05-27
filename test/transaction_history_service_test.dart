import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/services/transaction_history_service.dart';

void main() {
  test('builds a reverse chronological buy and sell timeline', () {
    final events = TransactionHistoryService.eventsFor([
      Asset(
        id: 'gold',
        type: AssetType.gold,
        amount: 20,
        unit: 'g',
        boughtDate: DateTime(2025, 1, 1),
        boughtPrice: 1000,
        soldDate: DateTime(2026, 1, 1),
        soldPrice: 1300,
      ),
      Asset(
        id: 'cash',
        type: AssetType.cash,
        amount: 500,
        unit: 'USD',
        boughtDate: DateTime(2025, 5, 1),
      ),
    ]);

    expect(events, hasLength(3));
    expect(events.first.type, TransactionEventType.sold);
    expect(events.first.asset.id, 'gold');
    expect(events[1].asset.id, 'cash');
  });

  test('reports realized profit and loss in the transaction currency', () {
    final results = TransactionHistoryService.realizedProfitLossFor([
      Asset(
        id: 'silver',
        type: AssetType.silver,
        amount: 100,
        unit: 'g',
        currency: 'EUR',
        boughtPrice: 120,
        soldDate: DateTime(2026, 1, 1),
        soldPrice: 95,
      ),
    ]);

    expect(results.single.amount, -25);
    expect(results.single.currency, 'EUR');
  });
}
