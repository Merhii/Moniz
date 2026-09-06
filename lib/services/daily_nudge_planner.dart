import '../models/money_entry.dart';
import 'money_ledger.dart';

/// When, and whether, to nudge about logging.
class DailyNudgeSettings {
  const DailyNudgeSettings({
    this.isEnabled = false,
    this.hour = 20,
    this.minute = 30,
  });

  final bool isEnabled;
  final int hour;
  final int minute;

  DailyNudgeSettings copyWith({bool? isEnabled, int? hour, int? minute}) {
    return DailyNudgeSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }

  String get timeLabel {
    final suffix = hour < 12 ? 'am' : 'pm';
    final twelve = hour % 12 == 0 ? 12 : hour % 12;
    return '$twelve:${minute.toString().padLeft(2, '0')}$suffix';
  }

  @override
  bool operator ==(Object other) {
    return other is DailyNudgeSettings &&
        other.isEnabled == isEnabled &&
        other.hour == hour &&
        other.minute == minute;
  }

  @override
  int get hashCode => Object.hash(isEnabled, hour, minute);
}

/// Decides when the next "anything to log?" reminder should land.
///
/// The rule is deliberately about the *next* one only. A repeating daily
/// notification would be simpler, but it cannot know whether the day was
/// already logged, so it would nag people who are keeping up — which is the
/// fastest way to get notifications turned off for good.
class DailyNudgePlanner {
  const DailyNudgePlanner();

  static const notificationId = 700001;

  DateTime? nextNudgeAt({
    required DailyNudgeSettings settings,
    required List<MoneyEntry> entries,
    required DateTime now,
  }) {
    if (!settings.isEnabled) return null;

    final loggedToday = MoneyLedger.inRange(
      entries,
      DateRange.day(now),
    ).isNotEmpty;

    final todayAt = DateTime(
      now.year,
      now.month,
      now.day,
      settings.hour,
      settings.minute,
    );
    // Nothing to nudge about if the day is already logged, and no point
    // scheduling a time that has passed.
    if (!loggedToday && todayAt.isAfter(now)) return todayAt;

    return DateTime(
      now.year,
      now.month,
      now.day + 1,
      settings.hour,
      settings.minute,
    );
  }

  String get title => 'Anything to log?';

  String get body =>
      'A quick note now beats reconstructing the week on Sunday.';
}
