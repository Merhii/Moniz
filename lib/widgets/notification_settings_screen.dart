import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_topic.dart';
import '../providers/notification_preferences_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);
    final colors = context.kinetic;
    return LedgerFrame(
      cardless: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KineticText(
                  'Price alerts',
                  style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
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
            const KineticText('No notification topics available.', muted: true)
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
        ],
      ),
    );
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
        color: colors.foreground.withValues(alpha: 0.04),
        borderRadius: AppTheme.pillRadius,
      ),
      child: KineticText(
        '$activeCount / $totalCount on',
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
    final foreground = colors.foreground;
    final background = colors.foreground.withValues(alpha: 0.02);
    final borderColor = colors.border.withValues(alpha: 0.12);
    return Container(
      key: Key('notification_topic_${topic.id}'),
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.tightRadius,
        border: Border.all(
          color: borderColor,
          width: 1.0,
        ),
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
                          ).copyWith(color: foreground, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        KineticText(
                          topic.metadataLabel,
                          maxLines: 1,
                          style: AppTheme.bodyStyle(
                            colors,
                          ).copyWith(color: foreground.withValues(alpha: 0.60), fontSize: 12),
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
            activeTrackColor: colors.accent,
            inactiveThumbColor: colors.mutedForeground,
            inactiveTrackColor: colors.foreground.withValues(alpha: 0.12),
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
    final background = colors.foreground.withValues(alpha: 0.04);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.tightRadius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: Icon(icon, color: foreground, size: 23),
    );
  }
}
