import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_notification_service.dart';

final testNotificationSenderProvider = Provider<TestNotificationSender>(
  (ref) => localNotificationService,
);
