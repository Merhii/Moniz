import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/portfolio_snapshot.dart';
import 'package:moniz/models/notification_topic.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/providers/notification_preferences_provider.dart';
import 'package:moniz/providers/zakat_reminder_provider.dart';
import 'package:moniz/services/local_notification_service.dart';
import 'package:moniz/services/notification_preferences_service.dart';
import 'package:moniz/services/zakat_reminder_planner.dart';

/// Keeps subscriptions in memory. The real service writes to Hive, and a
/// write issued inside the fake-async zone never settles, hanging the test.
class _InMemoryPreferencesService implements NotificationPreferencesService {
  _InMemoryPreferencesService(Iterable<String> ids) : _ids = ids.toSet();

  Set<String> _ids;

  @override
  Set<String> readSubscribedTopicIds() => {..._ids};

  @override
  Future<Set<String>> setTopicSubscription({
    required NotificationTopic topic,
    required bool isSubscribed,
  }) async {
    _ids = {..._ids};
    isSubscribed ? _ids.add(topic.id) : _ids.remove(topic.id);
    return Set.unmodifiable(_ids);
  }

  @override
  Future<Set<String>> reconcileAvailableTopics(
    List<NotificationTopic> availableTopics,
  ) async {
    final available = availableTopics.map((topic) => topic.id).toSet();
    _ids = _ids.where(available.contains).toSet();
    return Set.unmodifiable(_ids);
  }
}

class _RecordingScheduler implements ReminderScheduler {
  final syncs = <List<ScheduledReminder>>[];
  var permissionRequests = 0;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> syncZakatReminders(List<ScheduledReminder> reminders) async {
    syncs.add(reminders);
  }

  @override
  Future<void> syncDailyNudge(ScheduledReminder? reminder) async {}
}

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_reminder_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(AssetTagAdapter());
    Hive.registerAdapter(AssetAdapter());
    Hive.registerAdapter(MetalPriceSnapshotAdapter());
    Hive.registerAdapter(ZakatScheduleModeAdapter());
    Hive.registerAdapter(NisabStandardAdapter());
    Hive.registerAdapter(ZakatSettingsAdapter());
    Hive.registerAdapter(ZakatPaymentRecordAdapter());
    Hive.registerAdapter(PortfolioSnapshotAdapter());
    await Hive.openBox<Asset>('assets');
    await Hive.openBox<MetalPriceSnapshot>('metalPrices');
    await Hive.openBox<ZakatSettings>('zakatSettings');
    await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
    await Hive.openBox<PortfolioSnapshot>('portfolioSnapshots');
    await Hive.openBox<dynamic>('uiPreferences');
  });

  setUp(() async {
    await Hive.box<Asset>('assets').clear();
    await Hive.box<ZakatSettings>('zakatSettings').clear();
    await Hive.box<ZakatPaymentRecord>('zakatPayments').clear();
    await Hive.box<dynamic>('uiPreferences').clear();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  Future<_RecordingScheduler> pumpSync(WidgetTester tester) async {
    final scheduler = _RecordingScheduler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: const MaterialApp(
          home: ZakatReminderSync(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
    return scheduler;
  }

  testWidgets('an unsubscribed owner gets nothing scheduled', (tester) async {
    await tester.runAsync(() async {
      await Hive.box<ZakatSettings>('zakatSettings').put(
        'settings',
        ZakatSettings(nextRamadanDueDate: DateTime.now().add(
          const Duration(days: 60),
        )),
      );
    });

    final scheduler = await pumpSync(tester);

    expect(scheduler.syncs.single, isEmpty);
    expect(scheduler.permissionRequests, 0);
  });

  testWidgets('subscribing schedules the reminders and asks once', (
    tester,
  ) async {
    final due = DateTime.now().add(const Duration(days: 60));
    await tester.runAsync(() async {
      await Hive.box<ZakatSettings>(
        'zakatSettings',
      ).put('settings', ZakatSettings(nextRamadanDueDate: due));
      await Hive.box<dynamic>('uiPreferences').put(
        NotificationPreferencesService.subscribedTopicIdsKey,
        [ZakatReminderPlanner.dueSoonTopicId,
         ZakatReminderPlanner.dueTodayTopicId],
      );
    });

    final scheduler = await pumpSync(tester);

    // The week-ahead warning and the day itself, both still in the future.
    expect(scheduler.syncs.single, hasLength(2));
    expect(scheduler.syncs.single.first.title, 'Zakat due in 7 days');
    // Permission is asked for at the point something is actually pending.
    expect(scheduler.permissionRequests, 1);
  });

  testWidgets('turning the topics off takes the reminders back down', (
    tester,
  ) async {
    final due = DateTime.now().add(const Duration(days: 60));
    await tester.runAsync(() async {
      await Hive.box<ZakatSettings>(
        'zakatSettings',
      ).put('settings', ZakatSettings(nextRamadanDueDate: due));
      await Hive.box<dynamic>('uiPreferences').put(
        NotificationPreferencesService.subscribedTopicIdsKey,
        [ZakatReminderPlanner.dueTodayTopicId],
      );
    });

    final scheduler = _RecordingScheduler();
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reminderSchedulerProvider.overrideWithValue(scheduler),
          notificationPreferencesServiceProvider.overrideWithValue(
            _InMemoryPreferencesService(
              const [ZakatReminderPlanner.dueTodayTopicId],
            ),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const ZakatReminderSync(child: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(scheduler.syncs.single, hasLength(1));

    final topic = capturedRef
        .read(notificationPreferencesProvider)
        .availableTopics
        .firstWhere((t) => t.id == ZakatReminderPlanner.dueTodayTopicId);
    await capturedRef
        .read(notificationPreferencesProvider.notifier)
        .setTopicSubscription(topic: topic, isSubscribed: false);
    await tester.pump();

    // An empty plan is still a sync: it is what cancels what is pending.
    expect(scheduler.syncs.last, isEmpty);
  });
}
