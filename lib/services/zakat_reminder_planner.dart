import '../models/asset.dart';
import '../models/zakat_settings.dart';
import 'zakat_engine.dart';

/// One notification the app intends to have waiting on a future date.
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.scheduledFor,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime scheduledFor;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) {
    return other is ScheduledReminder &&
        other.id == id &&
        other.scheduledFor == scheduledFor &&
        other.title == title &&
        other.body == body;
  }

  @override
  int get hashCode => Object.hash(id, scheduledFor, title, body);

  @override
  String toString() => 'ScheduledReminder($id, $scheduledFor, $title, $body)';
}

/// Works out which zakat reminders should be pending, from dates the engine
/// has already computed. Deliberately pure: no plugin, no clock of its own.
class ZakatReminderPlanner {
  const ZakatReminderPlanner();

  static const dueSoonTopicId = 'zakat.due.soon';
  static const dueTodayTopicId = 'zakat.due.today';
  static const dueSoonLeadDays = 7;

  /// Reminders are notified at this hour, local time. A date alone would fire
  /// at midnight, which reads as a nuisance rather than a reminder.
  static const notifyAtHour = 9;

  /// iOS keeps at most 64 notifications pending and silently drops the rest,
  /// so a large ledger must not crowd out the reminders that matter first.
  static const maxPending = 32;

  List<ScheduledReminder> plan({
    required ZakatResult result,
    required Set<String> subscribedTopicIds,
    required DateTime now,
  }) {
    final wantsDueSoon = subscribedTopicIds.contains(dueSoonTopicId);
    final wantsDueToday = subscribedTopicIds.contains(dueTodayTopicId);
    if (!wantsDueSoon && !wantsDueToday) return const [];

    final reminders = <ScheduledReminder>[];
    for (final due in _dueDates(result)) {
      if (wantsDueSoon) {
        final lead = _at(
          due.date.subtract(const Duration(days: dueSoonLeadDays)),
        );
        if (lead.isAfter(now)) {
          reminders.add(
            ScheduledReminder(
              id: _id(dueSoonTopicId, due.key),
              scheduledFor: lead,
              title: 'Zakat due in $dueSoonLeadDays days',
              body: '${due.subject} on ${_formatDate(due.date)}.',
            ),
          );
        }
      }
      if (wantsDueToday) {
        final onTheDay = _at(due.date);
        if (onTheDay.isAfter(now)) {
          reminders.add(
            ScheduledReminder(
              id: _id(dueTodayTopicId, due.key),
              scheduledFor: onTheDay,
              title: 'Zakat due today',
              body: '${due.subject} today.',
            ),
          );
        }
      }
    }

    reminders.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return List.unmodifiable(
      reminders.length > maxPending
          ? reminders.sublist(0, maxPending)
          : reminders,
    );
  }

  /// Ramadan mode settles the whole portfolio on one date, so one reminder
  /// covers it. Per-holding mode has an anniversary per holding.
  List<_DueDate> _dueDates(ZakatResult result) {
    if (result.settings.scheduleMode == ZakatScheduleMode.ramadanAnnual) {
      final date = result.settings.nextRamadanDueDate;
      if (date == null) return const [];
      return [
        _DueDate(key: ZakatEngine.annualPaymentKey, date: date, subject: 'Your zakat is due'),
      ];
    }

    final dates = <_DueDate>[];
    for (final assessment in result.assessments) {
      final date = assessment.nextDueDate;
      // A sold holding keeps a due date on its record but owes nothing.
      if (date == null || assessment.exclusionReason == ZakatEngine.soldExclusion) {
        continue;
      }
      dates.add(
        _DueDate(
          key: assessment.asset.id,
          date: date,
          subject: 'Zakat on your ${_describe(assessment)} is due',
        ),
      );
    }
    return dates;
  }

  String _describe(ZakatAssetAssessment assessment) {
    final asset = assessment.asset;
    final amount = _trim(asset.amount);
    return asset.type.isMetal
        ? '$amount ${asset.unit} of ${asset.type.label.toLowerCase()}'
        : '${asset.type.label.toLowerCase()} holding';
  }

  DateTime _at(DateTime date) {
    return DateTime(date.year, date.month, date.day, notifyAtHour);
  }

  /// Stable per topic and holding so a reschedule replaces the pending one
  /// rather than stacking a second copy beside it.
  int _id(String topicId, String key) {
    return notificationIdBase + Object.hash(topicId, key).abs() % idSpace;
  }

  static String _trim(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  /// Reminder ids live in their own range so cancelling them cannot disturb
  /// any other notification the app shows.
  static const notificationIdBase = 800000;
  static const idSpace = 100000;
}

class _DueDate {
  const _DueDate({
    required this.key,
    required this.date,
    required this.subject,
  });

  final String key;
  final DateTime date;
  final String subject;
}
