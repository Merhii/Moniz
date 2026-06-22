import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/models/notification_topic.dart';
import 'package:moniz/providers/notification_preferences_provider.dart';
import 'package:moniz/services/notification_preferences_service.dart';
import 'package:moniz/theme/app_theme.dart';
import 'package:moniz/widgets/notification_settings_screen.dart';

void main() {
  testWidgets('shows notification topics and persists alert toggles', (
    tester,
  ) async {
    final preferencesService = _InMemoryNotificationPreferencesService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPreferencesServiceProvider.overrideWithValue(
            preferencesService,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: NotificationSettingsScreen()),
          ),
        ),
      ),
    );

    expect(find.text('Price alerts'), findsOneWidget);
    expect(find.text('Gold price increased by 3%'), findsOneWidget);
    expect(find.text('Gold price decreased by 3%'), findsOneWidget);
    expect(find.text('Silver price increased/decreased by 3%'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('notification_topic_hit_gold.price.increase.3')),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(find.text('1 / 3 on'), findsOneWidget);
    expect(preferencesService.subscribedTopicIds, {'gold.price.increase.3'});

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _InMemoryNotificationPreferencesService
    implements NotificationPreferencesService {
  final subscribedTopicIds = <String>{};

  @override
  Set<String> readSubscribedTopicIds() {
    return Set.unmodifiable(subscribedTopicIds);
  }

  @override
  Future<Set<String>> setTopicSubscription({
    required NotificationTopic topic,
    required bool isSubscribed,
  }) async {
    if (isSubscribed) {
      subscribedTopicIds.add(topic.id);
    } else {
      subscribedTopicIds.remove(topic.id);
    }
    return Set.unmodifiable(subscribedTopicIds);
  }

  @override
  Future<Set<String>> reconcileAvailableTopics(
    List<NotificationTopic> availableTopics,
  ) async {
    final availableTopicIds = availableTopics.map((topic) => topic.id).toSet();
    subscribedTopicIds.removeWhere(
      (topicId) => !availableTopicIds.contains(topicId),
    );
    return Set.unmodifiable(subscribedTopicIds);
  }
}
