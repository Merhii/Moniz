import 'package:hive/hive.dart';

import '../models/notification_topic.dart';

abstract class NotificationSubscriptionGateway {
  Future<void> subscribe(NotificationTopic topic);

  Future<void> unsubscribe(NotificationTopic topic);

  Future<void> syncSubscriptions(List<NotificationTopic> topics);
}

class NoopPubSubSubscriptionGateway implements NotificationSubscriptionGateway {
  const NoopPubSubSubscriptionGateway();

  @override
  Future<void> subscribe(NotificationTopic topic) async {}

  @override
  Future<void> unsubscribe(NotificationTopic topic) async {}

  @override
  Future<void> syncSubscriptions(List<NotificationTopic> topics) async {}
}

class NotificationPreferencesService {
  NotificationPreferencesService({
    required Box<dynamic> preferencesBox,
    required NotificationSubscriptionGateway subscriptionGateway,
  }) : _preferencesBox = preferencesBox,
       _subscriptionGateway = subscriptionGateway;

  static const subscribedTopicIdsKey = 'notificationSubscribedTopicIds';

  final Box<dynamic> _preferencesBox;
  final NotificationSubscriptionGateway _subscriptionGateway;

  Set<String> readSubscribedTopicIds() {
    final value = _preferencesBox.get(subscribedTopicIdsKey);
    if (value is Iterable) {
      return value.whereType<String>().toSet();
    }
    return <String>{};
  }

  Future<Set<String>> setTopicSubscription({
    required NotificationTopic topic,
    required bool isSubscribed,
  }) async {
    final nextIds = readSubscribedTopicIds();
    if (isSubscribed) {
      await _subscriptionGateway.subscribe(topic);
      nextIds.add(topic.id);
    } else {
      await _subscriptionGateway.unsubscribe(topic);
      nextIds.remove(topic.id);
    }
    await _saveTopicIds(nextIds);
    return Set.unmodifiable(nextIds);
  }

  Future<Set<String>> reconcileAvailableTopics(
    List<NotificationTopic> availableTopics,
  ) async {
    final availableTopicIds = availableTopics.map((topic) => topic.id).toSet();
    final nextIds = readSubscribedTopicIds()
        .where(availableTopicIds.contains)
        .toSet();
    await _saveTopicIds(nextIds);
    await _subscriptionGateway.syncSubscriptions(
      availableTopics
          .where((topic) => nextIds.contains(topic.id))
          .toList(growable: false),
    );
    return Set.unmodifiable(nextIds);
  }

  Future<void> _saveTopicIds(Set<String> topicIds) {
    final sortedIds = topicIds.toList()..sort();
    return _preferencesBox.put(subscribedTopicIdsKey, sortedIds);
  }
}
