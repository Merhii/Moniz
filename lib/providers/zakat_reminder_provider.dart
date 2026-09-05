import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_notification_service.dart';
import '../services/zakat_engine.dart';
import '../services/zakat_reminder_planner.dart';
import 'asset_provider.dart';
import 'metal_price_provider.dart';
import 'notification_preferences_provider.dart';
import 'zakat_provider.dart';

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => localNotificationService,
);

/// What should be pending on the device right now. Recomputed whenever a
/// holding, the schedule, or the subscriptions change, so the reminders track
/// the ledger instead of drifting away from it.
final zakatReminderPlanProvider = Provider<List<ScheduledReminder>>((ref) {
  final subscribedTopicIds = ref.watch(
    notificationPreferencesProvider.select((state) => state.subscribedTopicIds),
  );
  final settings = ref.watch(zakatProvider);
  final assets = ref.watch(assetProvider);
  final prices = ref.watch(metalPriceProvider).snapshot;

  final now = DateTime.now();
  final result = ZakatEngine.calculate(
    assets: assets,
    prices: prices,
    settings: settings,
    payments: ref.read(zakatProvider.notifier).payments,
    today: now,
  );
  return const ZakatReminderPlanner().plan(
    result: result,
    subscribedTopicIds: subscribedTopicIds,
    now: now,
  );
});

/// Pushes [zakatReminderPlanProvider] onto the device. Mounted once, high in
/// the tree, so it keeps working while the owner is on any tab.
class ZakatReminderSync extends ConsumerStatefulWidget {
  const ZakatReminderSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ZakatReminderSync> createState() => _ZakatReminderSyncState();
}

class _ZakatReminderSyncState extends ConsumerState<ZakatReminderSync> {
  var _hadReminders = false;

  @override
  void initState() {
    super.initState();
    // Reminders live on the device, not in the app, so the first sync has to
    // wait for the first frame rather than run during the build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sync(ref.read(zakatReminderPlanProvider));
    });
  }

  Future<void> _sync(List<ScheduledReminder> plan) async {
    final scheduler = ref.read(reminderSchedulerProvider);
    // Ask only on the way from nothing pending to something pending: that is
    // the moment the owner actually asked for notifications.
    if (plan.isNotEmpty && !_hadReminders) {
      await scheduler.ensurePermission();
    }
    _hadReminders = plan.isNotEmpty;
    // A denied permission still leaves the schedule correct; it just will not
    // be shown. Nothing here should cost the owner the rest of the app.
    try {
      await scheduler.syncZakatReminders(plan);
    } catch (_) {
      // Ignored on purpose.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<ScheduledReminder>>(zakatReminderPlanProvider, (
      previous,
      next,
    ) {
      if (previous != null && _sameReminders(previous, next)) return;
      _sync(next);
    });
    return widget.child;
  }

  static bool _sameReminders(
    List<ScheduledReminder> a,
    List<ScheduledReminder> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
