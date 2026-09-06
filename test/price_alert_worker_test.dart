import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/services/metal_price_service.dart';
import 'package:moniz/services/price_alert_evaluator.dart';
import 'package:moniz/services/price_alert_store.dart';
import 'package:moniz/services/price_alert_worker.dart';

class _StubPriceService implements MetalPriceService {
  _StubPriceService(this.gold, this.silver);

  final double gold;
  final double silver;
  var calls = 0;

  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    calls++;
    return MetalPriceSnapshot(
      goldPerGramUsd: gold,
      silverPerGramUsd: silver,
      priceTimestamp: DateTime.utc(2026, 9, 6),
      fetchedAt: DateTime.utc(2026, 9, 6),
    );
  }
}

class _FailingPriceService implements MetalPriceService {
  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    throw const MetalPriceException('offline');
  }
}

void main() {
  const store = PriceAlertStore();
  const goldUp = 'gold.price.increase.3';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an unsubscribed owner costs no network request', () async {
    final service = _StubPriceService(200, 2);
    final shown = <PriceAlert>[];

    await runPriceAlertCheck(
      service: service,
      store: store,
      present: (alerts) async => shown.addAll(alerts),
    );

    expect(service.calls, 0, reason: 'nothing to check for');
    expect(shown, isEmpty);
  });

  test('the first check records a baseline and stays quiet', () async {
    await store.writeSubscribedTopicIds({goldUp});
    final shown = <PriceAlert>[];

    await runPriceAlertCheck(
      service: _StubPriceService(100, 1),
      store: store,
      present: (alerts) async => shown.addAll(alerts),
    );

    expect(shown, isEmpty);
    expect((await store.readBaseline()).goldPerGramUsd, 100);
  });

  test('a later check past the threshold notifies once, then rearms', () async {
    await store.writeSubscribedTopicIds({goldUp});
    await store.writeBaseline(const PriceAlertBaseline(goldPerGramUsd: 100));
    final shown = <PriceAlert>[];
    Future<void> present(List<PriceAlert> alerts) async => shown.addAll(alerts);

    await runPriceAlertCheck(
      service: _StubPriceService(104, 1),
      store: store,
      present: present,
    );
    expect(shown.single.title, 'Gold is up 4.0%');
    expect((await store.readBaseline()).goldPerGramUsd, 104);

    // Same price on the next run: the move was already reported.
    shown.clear();
    await runPriceAlertCheck(
      service: _StubPriceService(104, 1),
      store: store,
      present: present,
    );
    expect(shown, isEmpty);
  });

  test('a failed fetch leaves the baseline alone', () async {
    await store.writeSubscribedTopicIds({goldUp});
    await store.writeBaseline(const PriceAlertBaseline(goldPerGramUsd: 100));

    await expectLater(
      runPriceAlertCheck(service: _FailingPriceService(), store: store),
      throwsA(isA<MetalPriceException>()),
    );

    // Losing the baseline would make the next successful run measure from
    // nothing and silently skip a move.
    expect((await store.readBaseline()).goldPerGramUsd, 100);
  });

  test('subscriptions survive a round trip through the store', () async {
    await store.writeSubscribedTopicIds({goldUp, 'silver.price.movement.3'});

    expect(await store.readSubscribedTopicIds(), {
      goldUp,
      'silver.price.movement.3',
    });
  });

  test('clearing forgets the baseline so re-enabling starts fresh', () async {
    await store.writeBaseline(const PriceAlertBaseline(goldPerGramUsd: 100));
    await store.clearBaseline();

    expect((await store.readBaseline()).goldPerGramUsd, isNull);
  });
}
