import 'package:shared_preferences/shared_preferences.dart';

import 'price_alert_evaluator.dart';

/// The small amount of state the background check needs, kept where a
/// background isolate can reach it.
///
/// Deliberately not Hive: the app holds those boxes open, and Hive cannot open
/// the same box in two isolates. The subscriptions here are a one-way mirror
/// of the ones in `uiPreferences`, written by the app and only read by the
/// worker.
class PriceAlertStore {
  const PriceAlertStore();

  static const _topicIdsKey = 'priceAlert.subscribedTopicIds';
  static const _goldKey = 'priceAlert.baselineGoldPerGramUsd';
  static const _silverKey = 'priceAlert.baselineSilverPerGramUsd';

  Future<Set<String>> readSubscribedTopicIds() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_topicIdsKey) ?? const []).toSet();
  }

  Future<void> writeSubscribedTopicIds(Set<String> topicIds) async {
    final preferences = await SharedPreferences.getInstance();
    final sorted = topicIds.toList()..sort();
    await preferences.setStringList(_topicIdsKey, sorted);
  }

  Future<PriceAlertBaseline> readBaseline() async {
    final preferences = await SharedPreferences.getInstance();
    return PriceAlertBaseline(
      goldPerGramUsd: preferences.getDouble(_goldKey),
      silverPerGramUsd: preferences.getDouble(_silverKey),
    );
  }

  Future<void> writeBaseline(PriceAlertBaseline baseline) async {
    final preferences = await SharedPreferences.getInstance();
    await _put(preferences, _goldKey, baseline.goldPerGramUsd);
    await _put(preferences, _silverKey, baseline.silverPerGramUsd);
  }

  /// Forgetting the baseline when the last subscription goes means switching
  /// back on starts from today rather than reporting a move from months ago.
  Future<void> clearBaseline() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_goldKey);
    await preferences.remove(_silverKey);
  }

  Future<void> _put(SharedPreferences preferences, String key, double? value) {
    return value == null
        ? preferences.remove(key)
        : preferences.setDouble(key, value);
  }
}
