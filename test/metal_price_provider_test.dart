import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/providers/metal_price_provider.dart';
import 'package:moniz/services/metal_price_service.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_price_test_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(MetalPriceSnapshotAdapter());
  });

  setUp(() async {
    await Hive.openBox<MetalPriceSnapshot>('metalPrices');
    await Hive.box<MetalPriceSnapshot>('metalPrices').clear();
  });

  tearDown(() async {
    await Hive.box<MetalPriceSnapshot>('metalPrices').close();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('loads cached prices without making an API call', () async {
    final cachedSnapshot = _snapshot(gold: 100, silver: 1.2);
    await Hive.box<MetalPriceSnapshot>(
      'metalPrices',
    ).put('latest_usd_gram_prices', cachedSnapshot);
    final service = _FakeMetalPriceService(result: _snapshot());

    final notifier = MetalPriceNotifier(
      priceBox: Hive.box<MetalPriceSnapshot>('metalPrices'),
      priceService: service,
      historyService: const _FakeMetalPriceHistoryService(),
    );
    addTearDown(notifier.dispose);

    expect(notifier.state.snapshot?.goldPerGramUsd, 100);
    expect(notifier.state.isCached, isTrue);
    expect(service.callCount, 0);
  });

  test('refresh stores new live prices in the local cache', () async {
    final result = _snapshot(gold: 111, silver: 1.6);
    final notifier = MetalPriceNotifier(
      priceBox: Hive.box<MetalPriceSnapshot>('metalPrices'),
      priceService: _FakeMetalPriceService(result: result),
      historyService: _FakeMetalPriceHistoryService(
        result: [_snapshot(gold: 101, silver: 1.4)],
      ),
    );
    addTearDown(notifier.dispose);

    await notifier.refreshPrices();

    expect(notifier.state.snapshot?.goldPerGramUsd, 111);
    expect(notifier.state.isCached, isFalse);
    expect(
      Hive.box<MetalPriceSnapshot>(
        'metalPrices',
      ).get('latest_usd_gram_prices')?.silverPerGramUsd,
      1.6,
    );
    expect(notifier.state.historicalPrices.single.goldPerGramUsd, 101);
  });

  test('ignores another refresh while one is already in flight', () async {
    final service = _DelayedMetalPriceService();
    final notifier = MetalPriceNotifier(
      priceBox: Hive.box<MetalPriceSnapshot>('metalPrices'),
      priceService: service,
      historyService: const _FakeMetalPriceHistoryService(),
    );
    addTearDown(notifier.dispose);

    final firstRefresh = notifier.refreshPrices();
    final secondRefresh = notifier.refreshPrices();

    expect(service.callCount, 1);
    service.complete(_snapshot());
    await Future.wait([firstRefresh, secondRefresh]);
    expect(notifier.state.isRefreshing, isFalse);
  });

  test('keeps cached prices visible when refresh fails', () async {
    await Hive.box<MetalPriceSnapshot>(
      'metalPrices',
    ).put('latest_usd_gram_prices', _snapshot(gold: 105));
    final notifier = MetalPriceNotifier(
      priceBox: Hive.box<MetalPriceSnapshot>('metalPrices'),
      priceService: _FakeMetalPriceService(
        error: const MetalPriceException('Service unavailable.'),
      ),
      historyService: const _FakeMetalPriceHistoryService(),
    );
    addTearDown(notifier.dispose);

    await notifier.refreshPrices();

    expect(notifier.state.snapshot?.goldPerGramUsd, 105);
    expect(notifier.state.isCached, isTrue);
    expect(notifier.state.errorMessage, 'Service unavailable.');
  });
}

MetalPriceSnapshot _snapshot({double gold = 109, double silver = 1.4}) {
  return MetalPriceSnapshot(
    goldPerGramUsd: gold,
    silverPerGramUsd: silver,
    priceTimestamp: DateTime.utc(2026, 5, 27, 10),
    fetchedAt: DateTime.utc(2026, 5, 27, 10),
  );
}

class _FakeMetalPriceService implements MetalPriceService {
  _FakeMetalPriceService({this.result, this.error});

  final MetalPriceSnapshot? result;
  final MetalPriceException? error;
  int callCount = 0;

  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    callCount += 1;
    if (error != null) throw error!;
    return result!;
  }
}

class _DelayedMetalPriceService implements MetalPriceService {
  final _result = Completer<MetalPriceSnapshot>();
  int callCount = 0;

  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() {
    callCount += 1;
    return _result.future;
  }

  void complete(MetalPriceSnapshot snapshot) {
    _result.complete(snapshot);
  }
}

class _FakeMetalPriceHistoryService implements MetalPriceHistoryService {
  const _FakeMetalPriceHistoryService({this.result = const []});

  final List<MetalPriceSnapshot> result;

  @override
  Future<List<MetalPriceSnapshot>> fetchWeeklyAverages({
    required int days,
  }) async {
    return result;
  }
}
