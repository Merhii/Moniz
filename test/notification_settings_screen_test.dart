import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/models/notification_topic.dart';
import 'package:moniz/providers/local_notification_provider.dart';
import 'package:moniz/providers/notification_preferences_provider.dart';
import 'package:moniz/services/local_notification_service.dart';
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

    expect(find.text('PRICE ALERTS'), findsOneWidget);
    expect(find.text('GOLD PRICE INCREASED BY 3%'), findsOneWidget);
    expect(find.text('GOLD PRICE DECREASED BY 3%'), findsOneWidget);
    expect(find.text('SILVER PRICE INCREASED/DECREASED BY 3%'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('notification_topic_hit_gold.price.increase.3')),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(find.text('1 / 3 ON'), findsOneWidget);
    expect(preferencesService.subscribedTopicIds, {'gold.price.increase.3'});

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sends a debug test notification on demand', (tester) async {
    final sender = _FakeTestNotificationSender();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPreferencesServiceProvider.overrideWithValue(
            _InMemoryNotificationPreferencesService(),
          ),
          testNotificationSenderProvider.overrideWithValue(sender),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: NotificationSettingsScreen()),
          ),
        ),
      ),
    );

    final testButton = find.byKey(const Key('send_test_notification'));
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pump();

    expect(sender.sendCount, 1);
    expect(
      find.text('Test sent. Check the banner or Notification Centre.'),
      findsOneWidget,
    );
  });
}

class _FakeTestNotificationSender implements TestNotificationSender {
  var sendCount = 0;

  @override
  Future<TestNotificationResult> sendTestNotification() async {
    sendCount += 1;
    return TestNotificationResult.sent;
  }
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
