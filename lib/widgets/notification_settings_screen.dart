import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_topic.dart';
import '../providers/local_notification_provider.dart';
import '../providers/notification_preferences_provider.dart';
import '../services/local_notification_service.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  var _isSendingTest = false;
  String? _testStatus;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);
    final colors = context.kinetic;
    return LedgerFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KineticText(
                  'PRICE ALERTS',
                  style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
                ),
              ),
              _TopicCountPill(
                activeCount: state.subscribedTopicIds.length,
                totalCount: state.availableTopics.length,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.availableTopics.isEmpty)
            const KineticText('NO NOTIFICATION TOPICS AVAILABLE.', muted: true)
          else
            ...state.availableTopics.map(
              (topic) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NotificationTopicToggle(
                  topic: topic,
                  isSubscribed: state.isSubscribed(topic),
                  isSyncing: state.isSyncing,
                  onChanged: (isSubscribed) => notifier.setTopicSubscription(
                    topic: topic,
                    isSubscribed: isSubscribed,
                  ),
                ),
              ),
            ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 2),
            KineticText(
              state.errorMessage!,
              key: const Key('notification_preferences_error'),
              uppercase: false,
              style: AppTheme.bodyStyle(colors).copyWith(color: colors.loss),
            ),
          ],
          if (kDebugMode) ...[
            const SizedBox(height: 4),
            Container(
              key: const Key('notification_debug_panel'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.muted.withValues(alpha: 0.58),
                borderRadius: AppTheme.tightRadius,
                border: Border.all(
                  color: colors.border,
                  width: AppTheme.thickBorderWidth,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KineticText('DEBUG TEST', style: AppTheme.labelStyle(colors)),
                  const SizedBox(height: 8),
                  BrutalistButton(
                    key: const Key('send_test_notification'),
                    label: _isSendingTest
                        ? 'SENDING...'
                        : 'SEND TEST NOTIFICATION',
                    expand: true,
                    tone: BrutalistButtonTone.primary,
                    onPressed: _isSendingTest ? null : _sendTestNotification,
                  ),
                  if (_testStatus != null) ...[
                    const SizedBox(height: 8),
                    KineticText(
                      _testStatus!,
                      key: const Key('notification_test_status'),
                      muted: true,
                      uppercase: false,
                      style: AppTheme.bodyStyle(colors).copyWith(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    setState(() {
      _isSendingTest = true;
      _testStatus = null;
    });
    try {
      final result = await ref
          .read(testNotificationSenderProvider)
          .sendTestNotification();
      if (!mounted) return;
      setState(() {
        _testStatus = switch (result) {
          TestNotificationResult.sent =>
            'Test sent. Check the banner or Notification Centre.',
          TestNotificationResult.permissionDenied =>
            'Notification permission is off. Enable it in device Settings.',
        };
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to send test notification: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _testStatus = 'Could not send the test notification.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSendingTest = false;
        });
      }
    }
  }
}

class _TopicCountPill extends StatelessWidget {
  const _TopicCountPill({required this.activeCount, required this.totalCount});

  final int activeCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.44),
        borderRadius: AppTheme.pillRadius,
        border: Border.all(
          color: colors.border,
          width: AppTheme.thickBorderWidth,
        ),
      ),
      child: KineticText(
        '$activeCount / $totalCount ON',
        style: AppTheme.labelStyle(colors),
      ),
    );
  }
}

class _NotificationTopicToggle extends StatelessWidget {
  const _NotificationTopicToggle({
    required this.topic,
    required this.isSubscribed,
    required this.isSyncing,
    required this.onChanged,
  });

  final NotificationTopic topic;
  final bool isSubscribed;
  final bool isSyncing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final foreground = isSubscribed
        ? colors.accentForeground
        : colors.foreground;
    final background = isSubscribed
        ? colors.accent
        : colors.background.withValues(alpha: 0.42);
    final borderColor = isSubscribed ? colors.accent : colors.border;
    return AnimatedContainer(
      key: Key('notification_topic_${topic.id}'),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppTheme.fast,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.tightRadius,
        border: Border.all(
          color: borderColor,
          width: AppTheme.thickBorderWidth,
        ),
        boxShadow: isSubscribed ? AppTheme.glowShadow(colors) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: PressableScale(
              key: Key('notification_topic_hit_${topic.id}'),
              onTap: isSyncing ? null : () => onChanged(!isSubscribed),
              scale: 0.98,
              child: Row(
                children: [
                  _TopicSignalIcon(topic: topic, isSubscribed: isSubscribed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KineticText(
                          topic.title,
                          maxLines: 2,
                          style: AppTheme.titleStyle(
                            colors,
                          ).copyWith(color: foreground, fontSize: 20),
                        ),
                        const SizedBox(height: 6),
                        KineticText(
                          topic.metadataLabel,
                          maxLines: 1,
                          style: AppTheme.bodyStyle(
                            colors,
                          ).copyWith(color: foreground, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            key: Key('notification_topic_toggle_${topic.id}'),
            value: isSubscribed,
            onChanged: isSyncing ? null : onChanged,
            activeThumbColor: colors.accentForeground,
            activeTrackColor: colors.accentForeground.withValues(alpha: 0.34),
            inactiveThumbColor: colors.mutedForeground,
            inactiveTrackColor: colors.muted.withValues(alpha: 0.58),
          ),
        ],
      ),
    );
  }
}

class _TopicSignalIcon extends StatelessWidget {
  const _TopicSignalIcon({required this.topic, required this.isSubscribed});

  final NotificationTopic topic;
  final bool isSubscribed;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final icon = switch (topic.direction) {
      NotificationTopicDirection.increase => Icons.trending_up,
      NotificationTopicDirection.decrease => Icons.trending_down,
      NotificationTopicDirection.either => Icons.sync_alt,
    };
    final foreground = isSubscribed
        ? colors.accent
        : topic.direction == NotificationTopicDirection.decrease
        ? colors.loss
        : colors.profit;
    final background = isSubscribed
        ? colors.accentForeground
        : colors.muted.withValues(alpha: 0.86);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.tightRadius,
        border: Border.all(
          color: isSubscribed ? colors.accentForeground : colors.border,
          width: AppTheme.thickBorderWidth,
        ),
      ),
      child: Icon(icon, color: foreground, size: 23),
    );
  }
}
