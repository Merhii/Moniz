import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../services/daily_nudge_planner.dart';
import '../services/zakat_reminder_planner.dart';
import 'money_entry_provider.dart';
import 'zakat_reminder_provider.dart';

class DailyNudgeNotifier extends StateNotifier<DailyNudgeSettings> {
  DailyNudgeNotifier({Box<dynamic>? preferencesBox})
    : _box = preferencesBox ?? Hive.box<dynamic>('uiPreferences'),
      super(_read(preferencesBox ?? Hive.box<dynamic>('uiPreferences')));

  final Box<dynamic> _box;

  static const enabledKey = 'dailyNudgeEnabled';
  static const hourKey = 'dailyNudgeHour';
  static const minuteKey = 'dailyNudgeMinute';

  static DailyNudgeSettings _read(Box<dynamic> box) {
    const fallback = DailyNudgeSettings();
    return DailyNudgeSettings(
      isEnabled: box.get(enabledKey) as bool? ?? fallback.isEnabled,
      hour: box.get(hourKey) as int? ?? fallback.hour,
      minute: box.get(minuteKey) as int? ?? fallback.minute,
    );
  }

  Future<void> setEnabled(bool isEnabled) async {
    await _box.put(enabledKey, isEnabled);
    state = state.copyWith(isEnabled: isEnabled);
  }

  Future<void> setTime({required int hour, required int minute}) async {
    await _box.putAll({hourKey: hour, minuteKey: minute});
    state = state.copyWith(hour: hour, minute: minute);
  }
}

final dailyNudgeProvider =
    StateNotifierProvider<DailyNudgeNotifier, DailyNudgeSettings>(
      (ref) => DailyNudgeNotifier(),
    );

/// What should be pending right now: one reminder, or none.
final dailyNudgePlanProvider = Provider<ScheduledReminder?>((ref) {
  const planner = DailyNudgePlanner();
  final at = planner.nextNudgeAt(
    settings: ref.watch(dailyNudgeProvider),
    entries: ref.watch(moneyEntryProvider),
    now: DateTime.now(),
  );
  if (at == null) return null;
  return ScheduledReminder(
    id: DailyNudgePlanner.notificationId,
    scheduledFor: at,
    title: planner.title,
    body: planner.body,
  );
});

/// Pushes the plan onto the device. Mounted once, high in the tree, so logging
/// an entry moves tonight's nudge to tomorrow without anything else asking.
class DailyNudgeSync extends ConsumerStatefulWidget {
  const DailyNudgeSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DailyNudgeSync> createState() => _DailyNudgeSyncState();
}

class _DailyNudgeSyncState extends ConsumerState<DailyNudgeSync> {
  var _hadNudge = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sync(ref.read(dailyNudgePlanProvider));
    });
  }

  Future<void> _sync(ScheduledReminder? plan) async {
    final scheduler = ref.read(reminderSchedulerProvider);
    // Ask only on the way from nothing pending to something pending.
    if (plan != null && !_hadNudge) {
      await scheduler.ensurePermission();
    }
    _hadNudge = plan != null;
    try {
      await scheduler.syncDailyNudge(plan);
    } catch (_) {
      // A reminder is a convenience. Losing it must not cost the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ScheduledReminder?>(dailyNudgePlanProvider, (previous, next) {
      if (previous == next) return;
      _sync(next);
    });
    return widget.child;
  }
}
