/// What a topic is about. Price moves need a server or a background fetch to
/// notice them; a zakat due date is a timestamp the app already knows, so the
/// two are delivered by completely different machinery.
enum NotificationTopicKind { priceMove, zakatDue }

enum NotificationTopicDirection { increase, decrease, either }

extension NotificationTopicDirectionLabel on NotificationTopicDirection {
  String get label {
    switch (this) {
      case NotificationTopicDirection.increase:
        return 'Increase';
      case NotificationTopicDirection.decrease:
        return 'Decrease';
      case NotificationTopicDirection.either:
        return 'Increase / decrease';
    }
  }
}

class NotificationTopic {
  const NotificationTopic({
    required this.id,
    required this.title,
    required this.subjectKey,
    required this.subjectLabel,
    required this.metricKey,
    required this.direction,
    required this.thresholdPercent,
    this.description,
  }) : kind = NotificationTopicKind.priceMove,
       leadDays = 0;

  /// A reminder fired [leadDays] before a zakat due date; 0 means on the day.
  const NotificationTopic.zakatDue({
    required this.id,
    required this.title,
    required this.leadDays,
    this.description,
  }) : kind = NotificationTopicKind.zakatDue,
       subjectKey = 'zakat',
       subjectLabel = 'Zakat',
       metricKey = 'dueDate',
       direction = NotificationTopicDirection.either,
       thresholdPercent = 0;

  final String id;
  final String title;
  final NotificationTopicKind kind;
  final int leadDays;
  final String subjectKey;
  final String subjectLabel;
  final String metricKey;
  final NotificationTopicDirection direction;
  final double thresholdPercent;
  final String? description;

  String get thresholdLabel => '${thresholdPercent.toStringAsFixed(0)}%';

  String get metadataLabel {
    switch (kind) {
      case NotificationTopicKind.priceMove:
        return '$subjectLabel / ${direction.label} / $thresholdLabel';
      case NotificationTopicKind.zakatDue:
        return leadDays == 0
            ? '$subjectLabel / On the day'
            : '$subjectLabel / $leadDays days ahead';
    }
  }
}
