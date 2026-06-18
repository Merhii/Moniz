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
  });

  final String id;
  final String title;
  final String subjectKey;
  final String subjectLabel;
  final String metricKey;
  final NotificationTopicDirection direction;
  final double thresholdPercent;
  final String? description;

  String get thresholdLabel => '${thresholdPercent.toStringAsFixed(0)}%';

  String get metadataLabel {
    return '$subjectLabel / ${direction.label} / $thresholdLabel';
  }
}
