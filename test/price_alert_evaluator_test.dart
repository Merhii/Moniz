import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/notification_topic.dart';
import 'package:moniz/services/notification_topic_catalog.dart';
import 'package:moniz/services/price_alert_evaluator.dart';

const evaluator = PriceAlertEvaluator();
final topics = const LocalNotificationTopicCatalog().availableTopics;

const goldUp = 'gold.price.increase.3';
const goldDown = 'gold.price.decrease.3';
const silverEither = 'silver.price.movement.3';

MetalPriceSnapshot _prices({double gold = 100, double silver = 1}) {
  return MetalPriceSnapshot(
    goldPerGramUsd: gold,
    silverPerGramUsd: silver,
    priceTimestamp: DateTime.utc(2026, 9, 6),
    fetchedAt: DateTime.utc(2026, 9, 6),
  );
}

PriceAlertOutcome _run({
  required MetalPriceSnapshot latest,
  required PriceAlertBaseline baseline,
  required Set<String> subscribed,
  List<NotificationTopic>? overrideTopics,
}) {
  return evaluator.evaluate(
    latest: latest,
    baseline: baseline,
    subscribedTopicIds: subscribed,
    topics: overrideTopics ?? topics,
  );
}

void main() {
  test('the first run only records a starting point', () {
    final outcome = _run(
      latest: _prices(gold: 100),
      baseline: const PriceAlertBaseline(),
      subscribed: {goldUp},
    );

    // Reporting a move here would be inventing one: the subscriber was never
    // shown the price it is being measured from.
    expect(outcome.alerts, isEmpty);
    expect(outcome.baseline.goldPerGramUsd, 100);
  });

  test('a move under the threshold says nothing and does not reset', () {
    final outcome = _run(
      latest: _prices(gold: 102.9),
      baseline: const PriceAlertBaseline(goldPerGramUsd: 100),
      subscribed: {goldUp},
    );

    expect(outcome.alerts, isEmpty);
    // Crucially the baseline stays at 100, so a drift to 103 later still fires
    // rather than being measured from 102.9 and lost.
    expect(outcome.baseline.goldPerGramUsd, 100);
  });

  test('crossing the threshold reports the move and where it came from', () {
    final outcome = _run(
      latest: _prices(gold: 103.5),
      baseline: const PriceAlertBaseline(goldPerGramUsd: 100),
      subscribed: {goldUp},
    );

    expect(outcome.alerts.single.title, 'Gold is up 3.5%');
    expect(
      outcome.alerts.single.body,
      'Now \$103.50 per gram, from \$100.00 when you were last told.',
    );
    // Reset, so the same 3.5% is not reported again on the next run.
    expect(outcome.baseline.goldPerGramUsd, 103.5);
  });

  test('an upward subscription ignores a fall, and the other way round', () {
    final fell = _run(
      latest: _prices(gold: 95),
      baseline: const PriceAlertBaseline(goldPerGramUsd: 100),
      subscribed: {goldUp},
    );
    expect(fell.alerts, isEmpty);
    expect(fell.baseline.goldPerGramUsd, 100);

    final rose = _run(
      latest: _prices(gold: 105),
      baseline: const PriceAlertBaseline(goldPerGramUsd: 100),
      subscribed: {goldDown},
    );
    expect(rose.alerts, isEmpty);
  });

  test('a downward subscription reports a fall', () {
    final outcome = _run(
      latest: _prices(gold: 96),
      baseline: const PriceAlertBaseline(goldPerGramUsd: 100),
      subscribed: {goldDown},
    );

    expect(outcome.alerts.single.title, 'Gold is down 4.0%');
  });

  test('silver moves in either direction', () {
    for (final price in [1.05, 0.95]) {
      final outcome = _run(
        latest: _prices(silver: price),
        baseline: const PriceAlertBaseline(silverPerGramUsd: 1),
        subscribed: {silverEither},
      );
      expect(outcome.alerts, hasLength(1), reason: 'at $price');
      expect(outcome.alerts.single.title, startsWith('Silver is'));
    }
  });

  test('one metal with both topics on is reported once, not twice', () {
    final outcome = _run(
      latest: _prices(gold: 104),
      baseline: const PriceAlertBaseline(goldPerGramUsd: 100),
      subscribed: {goldUp, goldDown},
    );

    expect(outcome.alerts, hasLength(1));
  });

  test('an unsubscribed metal is not measured at all', () {
    final outcome = _run(
      latest: _prices(gold: 200, silver: 2),
      baseline: const PriceAlertBaseline(
        goldPerGramUsd: 100,
        silverPerGramUsd: 1,
      ),
      subscribed: {silverEither},
    );

    expect(outcome.alerts.single.title, startsWith('Silver'));
    expect(outcome.baseline.goldPerGramUsd, 100, reason: 'untouched');
  });

  test('zakat topics are not price alerts and are skipped', () {
    final outcome = _run(
      latest: _prices(gold: 200),
      baseline: const PriceAlertBaseline(goldPerGramUsd: 100),
      subscribed: {'zakat.due.soon', 'zakat.due.today'},
    );

    expect(outcome.alerts, isEmpty);
  });

  test('a nonsense price is ignored rather than divided by', () {
    final outcome = _run(
      latest: _prices(gold: 0),
      baseline: const PriceAlertBaseline(goldPerGramUsd: 100),
      subscribed: {goldUp},
    );

    expect(outcome.alerts, isEmpty);
    expect(outcome.baseline.goldPerGramUsd, 100);
  });
}
