import '../models/metal_price_snapshot.dart';
import '../models/notification_topic.dart';

/// The prices a subscriber was last told about, per metal. A threshold is
/// measured from here rather than from a fixed window, so a move only counts
/// once and a slow drift eventually adds up to one.
class PriceAlertBaseline {
  const PriceAlertBaseline({this.goldPerGramUsd, this.silverPerGramUsd});

  final double? goldPerGramUsd;
  final double? silverPerGramUsd;

  double? forSubject(String subjectKey) {
    return switch (subjectKey) {
      'gold' => goldPerGramUsd,
      'silver' => silverPerGramUsd,
      _ => null,
    };
  }

  PriceAlertBaseline withSubject(String subjectKey, double price) {
    return switch (subjectKey) {
      'gold' => PriceAlertBaseline(
        goldPerGramUsd: price,
        silverPerGramUsd: silverPerGramUsd,
      ),
      'silver' => PriceAlertBaseline(
        goldPerGramUsd: goldPerGramUsd,
        silverPerGramUsd: price,
      ),
      _ => this,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PriceAlertBaseline &&
        other.goldPerGramUsd == goldPerGramUsd &&
        other.silverPerGramUsd == silverPerGramUsd;
  }

  @override
  int get hashCode => Object.hash(goldPerGramUsd, silverPerGramUsd);
}

class PriceAlert {
  const PriceAlert({
    required this.topicId,
    required this.title,
    required this.body,
  });

  final String topicId;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) {
    return other is PriceAlert &&
        other.topicId == topicId &&
        other.title == title &&
        other.body == body;
  }

  @override
  int get hashCode => Object.hash(topicId, title, body);

  @override
  String toString() => 'PriceAlert($topicId, $title, $body)';
}

class PriceAlertOutcome {
  const PriceAlertOutcome({required this.alerts, required this.baseline});

  final List<PriceAlert> alerts;

  /// The baseline to store after acting on [alerts]. Only metals that actually
  /// fired move, so an unreported move is never quietly forgotten.
  final PriceAlertBaseline baseline;
}

/// Decides which price alerts a fetch has earned. Pure, so the thresholds and
/// the ratchet can be tested without a device or a network.
class PriceAlertEvaluator {
  const PriceAlertEvaluator();

  PriceAlertOutcome evaluate({
    required MetalPriceSnapshot latest,
    required PriceAlertBaseline baseline,
    required Set<String> subscribedTopicIds,
    required List<NotificationTopic> topics,
  }) {
    var nextBaseline = baseline;
    final alerts = <PriceAlert>[];
    final firedSubjects = <String>{};

    for (final topic in topics) {
      if (topic.kind != NotificationTopicKind.priceMove) continue;
      if (!subscribedTopicIds.contains(topic.id)) continue;

      final current = _priceFor(latest, topic.subjectKey);
      if (current == null || current <= 0) continue;

      final previous = baseline.forSubject(topic.subjectKey);
      if (previous == null || previous <= 0) {
        // Nothing to compare against yet. Start the clock here rather than
        // reporting a move the subscriber was never shown the start of.
        nextBaseline = nextBaseline.withSubject(topic.subjectKey, current);
        continue;
      }

      final changePercent = (current - previous) / previous * 100;
      if (!_crosses(topic, changePercent)) continue;

      // One metal, several matching topics: report it once.
      if (!firedSubjects.add(topic.subjectKey)) continue;

      final rose = changePercent > 0;
      alerts.add(
        PriceAlert(
          topicId: topic.id,
          title: '${topic.subjectLabel} is '
              '${rose ? 'up' : 'down'} ${changePercent.abs().toStringAsFixed(1)}%',
          body: 'Now ${_formatUsd(current)} per gram, from '
              '${_formatUsd(previous)} when you were last told.',
        ),
      );
      nextBaseline = nextBaseline.withSubject(topic.subjectKey, current);
    }

    return PriceAlertOutcome(
      alerts: List.unmodifiable(alerts),
      baseline: nextBaseline,
    );
  }

  bool _crosses(NotificationTopic topic, double changePercent) {
    final threshold = topic.thresholdPercent;
    if (threshold <= 0) return false;
    return switch (topic.direction) {
      NotificationTopicDirection.increase => changePercent >= threshold,
      NotificationTopicDirection.decrease => changePercent <= -threshold,
      NotificationTopicDirection.either => changePercent.abs() >= threshold,
    };
  }

  double? _priceFor(MetalPriceSnapshot snapshot, String subjectKey) {
    return switch (subjectKey) {
      'gold' => snapshot.goldPerGramUsd,
      'silver' => snapshot.silverPerGramUsd,
      _ => null,
    };
  }

  static String _formatUsd(double value) => '\$${value.toStringAsFixed(2)}';
}
