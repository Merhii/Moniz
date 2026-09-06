import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../models/notification_topic.dart';
import 'metal_price_service.dart';
import 'notification_topic_catalog.dart';
import 'price_alert_evaluator.dart';
import 'price_alert_store.dart';

/// Name the periodic check is registered and cancelled under.
const priceAlertTaskName = 'moniz.priceAlertCheck';
const priceAlertTaskUniqueName = 'moniz.priceAlertCheck.periodic';

/// How often the OS is asked to run the check. Android treats this as a floor
/// and batches around doze, so the real gap is longer — often a few hours.
/// That is the trade for not holding a wakelock or an exact alarm.
const priceAlertInterval = Duration(hours: 6);

/// Ids for delivered price alerts, in their own range so they never collide
/// with the zakat reminders.
const priceAlertNotificationIdBase = 900000;

/// Runs in its own isolate with no access to the app's state, so everything it
/// needs comes from [PriceAlertStore] and the network.
@pragma('vm:entry-point')
void priceAlertCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runPriceAlertCheck();
      return true;
    } catch (_) {
      // Returning false asks the OS to retry with backoff. A failed price
      // fetch is usually just no connectivity, and the next scheduled run is
      // soon enough; retrying immediately would spend the owner's battery.
      return true;
    }
  });
}

/// How delivered alerts reach the owner. Injectable so the decision logic can
/// be tested without standing up the notification plugin.
typedef PriceAlertPresenter = Future<void> Function(List<PriceAlert> alerts);

@visibleForTesting
Future<void> runPriceAlertCheck({
  MetalPriceService? service,
  PriceAlertStore store = const PriceAlertStore(),
  PriceAlertPresenter? present,
}) async {
  final subscribed = await store.readSubscribedTopicIds();
  final topics = const LocalNotificationTopicCatalog().availableTopics;
  final wanted = topics
      .where((topic) => subscribed.contains(topic.id))
      .where((topic) => topic.kind == NotificationTopicKind.priceMove);
  if (wanted.isEmpty) return;

  final latest = await (service ?? GoldApiPriceService()).fetchLatestPrices();
  final outcome = const PriceAlertEvaluator().evaluate(
    latest: latest,
    baseline: await store.readBaseline(),
    subscribedTopicIds: subscribed,
    topics: topics,
  );

  // Saved before anything is shown: telling someone twice about the same move
  // is worse than the rare case of a saved baseline with no notification.
  await store.writeBaseline(outcome.baseline);
  if (outcome.alerts.isEmpty) return;

  await (present ?? _showPriceAlerts)(outcome.alerts);
}

Future<void> _showPriceAlerts(List<PriceAlert> alerts) async {
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_moniz'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'moniz_price_alerts',
      'Metal price alerts',
      channelDescription: 'Gold and silver moves past your chosen threshold.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  for (final alert in alerts) {
    await notifications.show(
      id: priceAlertNotificationIdBase + alert.topicId.hashCode.abs() % 1000,
      title: alert.title,
      body: alert.body,
      notificationDetails: details,
      payload: 'price.alert',
    );
  }
}

/// Starts or stops the periodic check to match what is subscribed.
class PriceAlertScheduler {
  const PriceAlertScheduler({this.store = const PriceAlertStore()});

  final PriceAlertStore store;

  /// Android only for now. iOS needs BGTaskScheduler set up natively before
  /// these toggles would mean anything there, and Moniz ships on Play first.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> sync(Set<String> subscribedPriceTopicIds) async {
    await store.writeSubscribedTopicIds(subscribedPriceTopicIds);
    if (!isSupported) return;

    if (subscribedPriceTopicIds.isEmpty) {
      await Workmanager().cancelByUniqueName(priceAlertTaskUniqueName);
      await store.clearBaseline();
      return;
    }

    await Workmanager().registerPeriodicTask(
      priceAlertTaskUniqueName,
      priceAlertTaskName,
      frequency: priceAlertInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
