import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'zakat_reminder_planner.dart';

enum TestNotificationResult { sent, permissionDenied }

abstract class TestNotificationSender {
  Future<TestNotificationResult> sendTestNotification();
}

/// Puts the reminders the app wants pending on the device, and takes down the
/// ones it no longer wants.
abstract class ReminderScheduler {
  Future<void> syncZakatReminders(List<ScheduledReminder> reminders);

  /// Asks for notification permission at the moment the owner turns something
  /// on, rather than on every resync.
  Future<bool> ensurePermission();
}

class LocalNotificationService
    implements TestNotificationSender, ReminderScheduler {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  var _isInitialized = false;
  var _isTimeZoneReady = false;

  Future<void> initialize() async {
    if (_isInitialized || kIsWeb || !_isSupportedPlatform) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_moniz'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    _isInitialized = true;
  }

  /// The plugin schedules against a named zone, and defaults to UTC. Reminders
  /// are meant for 09:00 where the owner is, so the device's own zone has to
  /// be loaded before anything is scheduled.
  Future<void> _prepareTimeZone() async {
    if (_isTimeZoneReady) return;
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // An unrecognised zone is not worth losing the reminder over; UTC still
      // fires on the right day, just not at the intended hour.
    }
    _isTimeZoneReady = true;
  }

  @override
  Future<bool> ensurePermission() async {
    await initialize();
    if (!_isSupportedPlatform) return false;
    return _requestPermission();
  }

  @override
  Future<void> syncZakatReminders(List<ScheduledReminder> reminders) async {
    await initialize();
    if (!_isSupportedPlatform) return;
    await _prepareTimeZone();

    // Cancel by reading back what is actually pending rather than tracking it
    // ourselves: a plan that changed while the app was closed still converges.
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (_isReminderId(pending.id)) {
        await _plugin.cancel(id: pending.id);
      }
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'moniz_zakat_reminders',
        'Zakat reminders',
        channelDescription: 'Reminders that zakat is coming due.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    for (final reminder in reminders) {
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime.from(reminder.scheduledFor, tz.local),
        notificationDetails: details,
        // Exact alarms need a permission Play restricts to alarm and calendar
        // apps. A zakat reminder does not need to land on the minute.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'zakat.reminder',
      );
    }
  }

  bool _isReminderId(int id) {
    const base = ZakatReminderPlanner.notificationIdBase;
    return id >= base && id < base + ZakatReminderPlanner.idSpace;
  }

  @override
  Future<TestNotificationResult> sendTestNotification() async {
    await initialize();
    final permissionGranted = await _requestPermission();
    if (!permissionGranted) return TestNotificationResult.permissionDenied;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'moniz_debug_notifications',
        'MONIZ test notifications',
        channelDescription: 'Notifications triggered manually in debug builds.',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    );

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: 'Moniz test alert',
      body: 'Gold moved +3.0%. Your local notification trigger is working.',
      notificationDetails: details,
      payload: 'debug.price-alert',
    );
    return TestNotificationResult.sent;
  }

  bool get _isSupportedPlatform {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<bool> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return granted ?? true;
    }

    return false;
  }
}

final localNotificationService = LocalNotificationService();
