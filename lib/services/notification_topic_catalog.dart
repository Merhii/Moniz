import '../models/notification_topic.dart';

abstract class NotificationTopicCatalog {
  List<NotificationTopic> get availableTopics;
}

class LocalNotificationTopicCatalog implements NotificationTopicCatalog {
  const LocalNotificationTopicCatalog();

  @override
  List<NotificationTopic> get availableTopics => const [
    NotificationTopic(
      id: 'gold.price.increase.3',
      title: 'Gold price increased by 3%',
      subjectKey: 'gold',
      subjectLabel: 'Gold',
      metricKey: 'price',
      direction: NotificationTopicDirection.increase,
      thresholdPercent: 3,
      description: 'Spot gold crosses the configured upward threshold.',
    ),
    NotificationTopic(
      id: 'gold.price.decrease.3',
      title: 'Gold price decreased by 3%',
      subjectKey: 'gold',
      subjectLabel: 'Gold',
      metricKey: 'price',
      direction: NotificationTopicDirection.decrease,
      thresholdPercent: 3,
      description: 'Spot gold crosses the configured downward threshold.',
    ),
    NotificationTopic(
      id: 'silver.price.movement.3',
      title: 'Silver price increased/decreased by 3%',
      subjectKey: 'silver',
      subjectLabel: 'Silver',
      metricKey: 'price',
      direction: NotificationTopicDirection.either,
      thresholdPercent: 3,
      description: 'Spot silver moves across either configured threshold.',
    ),
    NotificationTopic.zakatDue(
      id: 'zakat.due.soon',
      title: 'Zakat due in a week',
      leadDays: 7,
      description: 'A week before a holding completes its lunar year, or '
          'before your Ramadan date.',
    ),
    NotificationTopic.zakatDue(
      id: 'zakat.due.today',
      title: 'Zakat due today',
      leadDays: 0,
      description: 'On the day zakat becomes payable.',
    ),
  ];
}
