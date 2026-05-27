import '../models/asset.dart';

enum TransactionEventType { acquired, sold }

class TransactionEvent {
  const TransactionEvent({
    required this.asset,
    required this.type,
    required this.date,
    this.price,
  });

  final Asset asset;
  final TransactionEventType type;
  final DateTime date;
  final double? price;
}

class RealizedProfitLoss {
  const RealizedProfitLoss({
    required this.asset,
    required this.amount,
    required this.currency,
  });

  final Asset asset;
  final double amount;
  final String currency;
}

class TransactionHistoryService {
  static List<TransactionEvent> eventsFor(List<Asset> assets) {
    final events = <TransactionEvent>[];
    for (final asset in assets) {
      if (asset.boughtDate != null) {
        events.add(
          TransactionEvent(
            asset: asset,
            type: TransactionEventType.acquired,
            date: asset.boughtDate!,
            price: asset.boughtPrice,
          ),
        );
      }
      if (asset.soldDate != null) {
        events.add(
          TransactionEvent(
            asset: asset,
            type: TransactionEventType.sold,
            date: asset.soldDate!,
            price: asset.soldPrice,
          ),
        );
      }
    }
    events.sort((a, b) => b.date.compareTo(a.date));
    return events;
  }

  static List<RealizedProfitLoss> realizedProfitLossFor(List<Asset> assets) {
    return assets
        .where(
          (asset) =>
              asset.isSold &&
              asset.boughtPrice != null &&
              asset.soldPrice != null,
        )
        .map(
          (asset) => RealizedProfitLoss(
            asset: asset,
            amount: asset.soldPrice! - asset.boughtPrice!,
            currency: asset.currency,
          ),
        )
        .toList();
  }
}
