import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_topic.dart';
import '../services/price_alert_worker.dart';
import 'notification_preferences_provider.dart';

final priceAlertSchedulerProvider = Provider<PriceAlertScheduler>(
  (ref) => const PriceAlertScheduler(),
);

/// Just the price-move subscriptions. The zakat ones are delivered from
/// timestamps the app already knows and never involve the background check.
final subscribedPriceTopicIdsProvider = Provider<Set<String>>((ref) {
  final state = ref.watch(notificationPreferencesProvider);
  return Set.unmodifiable(
    state.availableTopics
        .where((topic) => topic.kind == NotificationTopicKind.priceMove)
        .where((topic) => state.subscribedTopicIds.contains(topic.id))
        .map((topic) => topic.id),
  );
});

/// Keeps the background price check registered only while somebody wants it,
/// and mirrors the subscriptions somewhere the worker's isolate can read.
class PriceAlertSync extends ConsumerStatefulWidget {
  const PriceAlertSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PriceAlertSync> createState() => _PriceAlertSyncState();
}

class _PriceAlertSyncState extends ConsumerState<PriceAlertSync> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sync(ref.read(subscribedPriceTopicIdsProvider));
    });
  }

  Future<void> _sync(Set<String> topicIds) async {
    try {
      await ref.read(priceAlertSchedulerProvider).sync(topicIds);
    } catch (_) {
      // Background scheduling is a convenience. Losing it should never cost
      // access to the ledger.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Set<String>>(subscribedPriceTopicIdsProvider, (previous, next) {
      if (previous != null && setEquals(previous, next)) return;
      _sync(next);
    });
    return widget.child;
  }
}
