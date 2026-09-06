import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/providers/daily_nudge_provider.dart';
import 'package:moniz/providers/zakat_reminder_provider.dart';
import 'package:moniz/services/daily_nudge_planner.dart';
import 'package:moniz/services/local_notification_service.dart';
import 'package:moniz/services/zakat_reminder_planner.dart';

class _RecordingScheduler implements ReminderScheduler {
  final nudges = <ScheduledReminder?>[];
  var permissionRequests = 0;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> syncZakatReminders(List<ScheduledReminder> reminders) async {}

  @override
  Future<void> syncDailyNudge(ScheduledReminder? reminder) async {
    nudges.add(reminder);
  }
}

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_nudge_');
    Hive.init(hiveDirectory.path);
    registerMonizAdapters();
    await Hive.openBox<MoneyEntry>('moneyEntries');
    await Hive.openBox<dynamic>('uiPreferences');
  });

  setUp(() async {
    await Hive.box<MoneyEntry>('moneyEntries').clear();
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
        overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
        child: const MaterialApp(
          home: DailyNudgeSync(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
    return scheduler;
  }

  testWidgets('nothing is scheduled while the nudge is off', (tester) async {
    final scheduler = await pumpSync(tester);

    expect(scheduler.nudges.single, isNull);
    expect(scheduler.permissionRequests, 0);
  });

  testWidgets('turning it on schedules one reminder and asks once', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<dynamic>('uiPreferences').putAll({
        DailyNudgeNotifier.enabledKey: true,
        DailyNudgeNotifier.hourKey: 23,
        DailyNudgeNotifier.minuteKey: 59,
      });
    });

    final scheduler = await pumpSync(tester);

    final nudge = scheduler.nudges.single;
    expect(nudge, isNotNull);
    expect(nudge!.id, DailyNudgePlanner.notificationId);
    expect(nudge.title, 'Anything to log?');
    expect(scheduler.permissionRequests, 1);
  });

  testWidgets('a day already logged is scheduled for tomorrow', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.runAsync(() async {
      await Hive.box<dynamic>('uiPreferences').putAll({
        DailyNudgeNotifier.enabledKey: true,
        DailyNudgeNotifier.hourKey: 23,
        DailyNudgeNotifier.minuteKey: 59,
      });
      await Hive.box<MoneyEntry>('moneyEntries').put(
        'logged',
        MoneyEntry(
          id: 'logged',
          amount: 5,
          direction: MoneyDirection.expense,
          happenedAt: now,
        ),
      );
    });

    final scheduler = await pumpSync(tester);

    // Somebody keeping up should not be nagged; that is how notifications get
    // switched off for good.
    expect(scheduler.nudges.single!.scheduledFor.day, isNot(now.day));
  });

  testWidgets('the reminder uses one id so rescheduling moves it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<dynamic>('uiPreferences').putAll({
        DailyNudgeNotifier.enabledKey: true,
        DailyNudgeNotifier.hourKey: 23,
        DailyNudgeNotifier.minuteKey: 59,
      });
    });
    final scheduler = await pumpSync(tester);

    expect(
      scheduler.nudges.whereType<ScheduledReminder>().map((n) => n.id).toSet(),
      {DailyNudgePlanner.notificationId},
    );
  });

  test('the settings survive a round trip through preferences', () async {
    final notifier = DailyNudgeNotifier(
      preferencesBox: Hive.box<dynamic>('uiPreferences'),
    );
    await notifier.setEnabled(true);
    await notifier.setTime(hour: 7, minute: 5);

    final reopened = DailyNudgeNotifier(
      preferencesBox: Hive.box<dynamic>('uiPreferences'),
    );
    expect(reopened.state.isEnabled, isTrue);
    expect(reopened.state.hour, 7);
    expect(reopened.state.minute, 5);
    expect(reopened.state.timeLabel, '7:05am');
  });
}
