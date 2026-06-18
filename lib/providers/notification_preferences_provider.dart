import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/notification_topic.dart';
import '../services/notification_preferences_service.dart';
import '../services/notification_topic_catalog.dart';

class NotificationPreferencesState {
  const NotificationPreferencesState({
    required this.availableTopics,
    required this.subscribedTopicIds,
    this.isSyncing = false,
    this.errorMessage,
  });

  final List<NotificationTopic> availableTopics;
  final Set<String> subscribedTopicIds;
  final bool isSyncing;
  final String? errorMessage;

  bool isSubscribed(NotificationTopic topic) {
    return subscribedTopicIds.contains(topic.id);
  }

  NotificationPreferencesState copyWith({
    List<NotificationTopic>? availableTopics,
    Set<String>? subscribedTopicIds,
    bool? isSyncing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotificationPreferencesState(
      availableTopics: availableTopics ?? this.availableTopics,
      subscribedTopicIds: subscribedTopicIds ?? this.subscribedTopicIds,
      isSyncing: isSyncing ?? this.isSyncing,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class NotificationPreferencesNotifier
    extends StateNotifier<NotificationPreferencesState> {
  NotificationPreferencesNotifier({
    required NotificationTopicCatalog topicCatalog,
    required NotificationPreferencesService preferencesService,
  }) : _preferencesService = preferencesService,
       super(_initialState(topicCatalog, preferencesService));

  final NotificationPreferencesService _preferencesService;

  static NotificationPreferencesState _initialState(
    NotificationTopicCatalog topicCatalog,
    NotificationPreferencesService preferencesService,
  ) {
    final availableTopics = List<NotificationTopic>.unmodifiable(
      topicCatalog.availableTopics,
    );
    final availableTopicIds = availableTopics.map((topic) => topic.id).toSet();
    final subscribedTopicIds = preferencesService
        .readSubscribedTopicIds()
        .where(availableTopicIds.contains)
        .toSet();
    return NotificationPreferencesState(
      availableTopics: availableTopics,
      subscribedTopicIds: Set<String>.unmodifiable(subscribedTopicIds),
    );
  }

  Future<void> toggleTopic(NotificationTopic topic) {
    return setTopicSubscription(
      topic: topic,
      isSubscribed: !state.isSubscribed(topic),
    );
  }

  Future<void> setTopicSubscription({
    required NotificationTopic topic,
    required bool isSubscribed,
  }) async {
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final subscribedTopicIds = await _preferencesService.setTopicSubscription(
        topic: topic,
        isSubscribed: isSubscribed,
      );
      if (!mounted) return;
      state = state.copyWith(
        subscribedTopicIds: subscribedTopicIds,
        isSyncing: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'Unable to save notification preferences right now.',
      );
    }
  }

  Future<void> reconcileSubscriptions() async {
    try {
      final subscribedTopicIds = await _preferencesService
          .reconcileAvailableTopics(state.availableTopics);
      if (!mounted) return;
      state = state.copyWith(subscribedTopicIds: subscribedTopicIds);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        errorMessage: 'Unable to sync notification preferences right now.',
      );
    }
  }
}

final notificationTopicCatalogProvider = Provider<NotificationTopicCatalog>(
  (ref) => const LocalNotificationTopicCatalog(),
);

final notificationSubscriptionGatewayProvider =
    Provider<NotificationSubscriptionGateway>(
      (ref) => const NoopPubSubSubscriptionGateway(),
    );

final notificationPreferencesServiceProvider =
    Provider<NotificationPreferencesService>(
      (ref) => NotificationPreferencesService(
        preferencesBox: Hive.box<dynamic>('uiPreferences'),
        subscriptionGateway: ref.read(notificationSubscriptionGatewayProvider),
      ),
    );

final notificationPreferencesProvider =
    StateNotifierProvider<
      NotificationPreferencesNotifier,
      NotificationPreferencesState
    >(
      (ref) => NotificationPreferencesNotifier(
        topicCatalog: ref.read(notificationTopicCatalogProvider),
        preferencesService: ref.read(notificationPreferencesServiceProvider),
      ),
    );
