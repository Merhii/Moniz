import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/asset.dart';
import '../models/portfolio_snapshot.dart';
import '../services/currency_converter.dart';
import '../services/portfolio_analytics.dart';

class PortfolioSnapshotNotifier extends StateNotifier<List<PortfolioSnapshot>> {
  PortfolioSnapshotNotifier({required Box<PortfolioSnapshot> snapshotBox})
    : _snapshotBox = snapshotBox,
      super(_sortedSnapshots(snapshotBox.values.toList()));

  final Box<PortfolioSnapshot> _snapshotBox;

  Future<void> capture(PortfolioAnalytics analytics) async {
    final cashUsd = _toUsd(analytics.categoryValuesUsd[AssetType.cash] ?? 0, analytics);
    final bankSavingsUsd = _toUsd(
      analytics.categoryValuesUsd[AssetType.bankSavings] ?? 0,
      analytics,
    );
    final goldUsd = _toUsd(analytics.categoryValuesUsd[AssetType.gold] ?? 0, analytics);
    final silverUsd = _toUsd(
      analytics.categoryValuesUsd[AssetType.silver] ?? 0,
      analytics,
    );
    final snapshot = PortfolioSnapshot(
      id: const Uuid().v4(),
      capturedAt: DateTime.now(),
      totalUsd: cashUsd + bankSavingsUsd + goldUsd + silverUsd,
      cashUsd: cashUsd,
      bankSavingsUsd: bankSavingsUsd,
      goldUsd: goldUsd,
      silverUsd: silverUsd,
    );
    await _snapshotBox.put(snapshot.id, snapshot);
    state = _sortedSnapshots(_snapshotBox.values.toList());
  }

  static double _toUsd(double value, PortfolioAnalytics analytics) {
    if (analytics.currency == CurrencyConverter.defaultCurrency) return value;
    return CurrencyConverter.convert(
          value,
          from: analytics.currency,
          to: CurrencyConverter.defaultCurrency,
        ) ??
        0;
  }

  static List<PortfolioSnapshot> _sortedSnapshots(
    List<PortfolioSnapshot> snapshots,
  ) {
    snapshots.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return snapshots;
  }
}

final portfolioSnapshotProvider =
    StateNotifierProvider<PortfolioSnapshotNotifier, List<PortfolioSnapshot>>(
      (ref) => PortfolioSnapshotNotifier(
        snapshotBox: Hive.box<PortfolioSnapshot>('portfolioSnapshots'),
      ),
    );
