import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:moniz/models/notification_topic.dart';
import 'package:moniz/providers/notification_preferences_provider.dart';
import 'package:moniz/services/notification_preferences_service.dart';
import 'package:moniz/theme/app_theme.dart';
import 'package:moniz/widgets/notification_settings_screen.dart';

void main() {
  late Directory hiveDirectory;

  // The screen carries the end-of-day nudge now, and that reads its settings
  // from the preferences box.
  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_notif_ui_');
    Hive.init(hiveDirectory.path);
    await Hive.openBox<dynamic>('uiPreferences');
  });

  setUp(() => Hive.box<dynamic>('uiPreferences').clear());

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  testWidgets('groups alert signals into selectable notification interests', (
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

    expect(find.text('Notification interests'), findsOneWidget);
    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('Silver'), findsOneWidget);
    expect(find.text('Zakat'), findsOneWidget);
    expect(find.text('0 / 3 selected'), findsOneWidget);

    // A due date is not a price feed and must not describe itself as one.
    // Short enough to survive the single line the row allows: the first
    // attempt rendered as "A week before zakat is due, and again ...".
    expect(
      find.text('A week before it is due, and on the day.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('notification_interest_hit_gold')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(find.text('1 / 3 selected'), findsOneWidget);
    expect(preferencesService.subscribedTopicIds, {
      'gold.price.increase.3',
      'gold.price.decrease.3',
    });

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
