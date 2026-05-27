import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/portfolio_snapshot.dart';
import 'package:moniz/providers/portfolio_snapshot_provider.dart';
import 'package:moniz/services/portfolio_analytics.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'moniz_snapshot_test_',
    );
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(PortfolioSnapshotAdapter());
  });

  setUp(() async {
    await Hive.openBox<PortfolioSnapshot>('portfolioSnapshots');
    await Hive.box<PortfolioSnapshot>('portfolioSnapshots').clear();
  });

  tearDown(() async {
    await Hive.box<PortfolioSnapshot>('portfolioSnapshots').close();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('captures portfolio total and category values locally', () async {
    final notifier = PortfolioSnapshotNotifier(
      snapshotBox: Hive.box<PortfolioSnapshot>('portfolioSnapshots'),
    );
    addTearDown(notifier.dispose);

    await notifier.capture(
      const PortfolioAnalytics(
        categoryValuesUsd: {
          AssetType.cash: 100,
          AssetType.bankSavings: 200,
          AssetType.gold: 300,
          AssetType.silver: 50,
        },
        totalUsd: 650,
        activeAssetCount: 4,
        soldAssetCount: 0,
        unvaluedAssetCount: 0,
      ),
    );

    expect(notifier.state.single.totalUsd, 650);
    expect(notifier.state.single.goldUsd, 300);
    expect(Hive.box<PortfolioSnapshot>('portfolioSnapshots').length, 1);
  });
}
