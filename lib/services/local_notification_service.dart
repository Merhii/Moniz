import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum TestNotificationResult { sent, permissionDenied }

abstract class TestNotificationSender {
  Future<TestNotificationResult> sendTestNotification();
}

class LocalNotificationService implements TestNotificationSender {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  var _isInitialized = false;

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
