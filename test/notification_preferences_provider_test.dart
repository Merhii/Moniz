import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:moniz/models/notification_topic.dart';
import 'package:moniz/providers/notification_preferences_provider.dart';
import 'package:moniz/services/notification_preferences_service.dart';
import 'package:moniz/services/notification_topic_catalog.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'moniz_notification_test_',
    );
    Hive.init(hiveDirectory.path);
    await Hive.openBox<dynamic>('uiPreferences');
  });

  setUp(() async {
    await Hive.box<dynamic>('uiPreferences').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('exposes default notification topics from the catalog', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(notificationPreferencesProvider);

    expect(state.availableTopics.map((topic) => topic.id), [
      'gold.price.increase.3',
      'gold.price.decrease.3',
      'silver.price.movement.3',
    ]);
  });

  test('persists subscriptions and calls the Pub/Sub gateway', () async {
    final gateway = _RecordingSubscriptionGateway();
    final container = ProviderContainer(
      overrides: [
        notificationSubscriptionGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    final topic = container
        .read(notificationPreferencesProvider)
        .availableTopics
        .first;

    await container
        .read(notificationPreferencesProvider.notifier)
        .setTopicSubscription(topic: topic, isSubscribed: true);

    expect(gateway.subscribedTopicIds, [topic.id]);
    expect(container.read(notificationPreferencesProvider).subscribedTopicIds, {
      topic.id,
    });
    expect(
      Hive.box<dynamic>(
        'uiPreferences',
      ).get(NotificationPreferencesService.subscribedTopicIdsKey),
      [topic.id],
    );

    await container
        .read(notificationPreferencesProvider.notifier)
        .setTopicSubscription(topic: topic, isSubscribed: false);

    expect(gateway.unsubscribedTopicIds, [topic.id]);
    expect(
      container.read(notificationPreferencesProvider).subscribedTopicIds,
      isEmpty,
    );
  });

  test('can use a different topic catalog without UI changes', () async {
    const customTopic = NotificationTopic(
      id: 'cash.balance.drop.5',
      title: 'Cash balance decreased by 5%',
      subjectKey: 'cash',
      subjectLabel: 'Cash',
      metricKey: 'balance',
      direction: NotificationTopicDirection.decrease,
      thresholdPercent: 5,
    );
    await Hive.box<dynamic>('uiPreferences').put(
      NotificationPreferencesService.subscribedTopicIdsKey,
      ['cash.balance.drop.5', 'removed.topic'],
    );
    final container = ProviderContainer(
      overrides: [
        notificationTopicCatalogProvider.overrideWithValue(
          const _FakeTopicCatalog([customTopic]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(notificationPreferencesProvider.notifier)
        .reconcileSubscriptions();

    final state = container.read(notificationPreferencesProvider);
    expect(state.availableTopics, [customTopic]);
    expect(state.subscribedTopicIds, {'cash.balance.drop.5'});
    expect(
      Hive.box<dynamic>(
        'uiPreferences',
      ).get(NotificationPreferencesService.subscribedTopicIdsKey),
      ['cash.balance.drop.5'],
    );
  });
}

class _RecordingSubscriptionGateway implements NotificationSubscriptionGateway {
  final subscribedTopicIds = <String>[];
  final unsubscribedTopicIds = <String>[];
  final syncedTopicIds = <String>[];

  @override
  Future<void> subscribe(NotificationTopic topic) async {
    subscribedTopicIds.add(topic.id);
  }

  @override
  Future<void> unsubscribe(NotificationTopic topic) async {
    unsubscribedTopicIds.add(topic.id);
  }

  @override
  Future<void> syncSubscriptions(List<NotificationTopic> topics) async {
    syncedTopicIds
      ..clear()
      ..addAll(topics.map((topic) => topic.id));
  }
}

class _FakeTopicCatalog implements NotificationTopicCatalog {
  const _FakeTopicCatalog(this.availableTopics);

  @override
  final List<NotificationTopic> availableTopics;
}
