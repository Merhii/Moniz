import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/asset.dart';
import '../models/portfolio_snapshot.dart';
import '../services/portfolio_analytics.dart';

class PortfolioSnapshotNotifier extends StateNotifier<List<PortfolioSnapshot>> {
  PortfolioSnapshotNotifier({required Box<PortfolioSnapshot> snapshotBox})
    : _snapshotBox = snapshotBox,
      super(_sortedSnapshots(snapshotBox.values.toList()));

  final Box<PortfolioSnapshot> _snapshotBox;

  Future<void> capture(PortfolioAnalytics analytics) async {
    final snapshot = PortfolioSnapshot(
      id: const Uuid().v4(),
      capturedAt: DateTime.now(),
      totalUsd: analytics.totalUsd,
      cashUsd: analytics.categoryValuesUsd[AssetType.cash] ?? 0,
      bankSavingsUsd: analytics.categoryValuesUsd[AssetType.bankSavings] ?? 0,
      goldUsd: analytics.categoryValuesUsd[AssetType.gold] ?? 0,
      silverUsd: analytics.categoryValuesUsd[AssetType.silver] ?? 0,
    );
    await _snapshotBox.put(snapshot.id, snapshot);
    state = _sortedSnapshots(_snapshotBox.values.toList());
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
