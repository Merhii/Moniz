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
    final interests = _NotificationInterest.fromTopics(state.availableTopics);
    final selectedInterestCount = interests
        .where((interest) => interest.isSelected(state.subscribedTopicIds))
        .length;
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
                  'Notification interests',
                  style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
                ),
              ),
              _TopicCountPill(
                activeCount: selectedInterestCount,
                totalCount: interests.length,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const KineticText(
            'Choose the topics you want to receive notifications about.',
            muted: true,
            uppercase: false,
          ),
          const SizedBox(height: 16),
          if (interests.isEmpty)
            const KineticText(
              'No notification interests available.',
              muted: true,
            )
          else
            ...interests.map(
              (interest) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NotificationInterestToggle(
                  interest: interest,
                  isSubscribed: interest.isSelected(state.subscribedTopicIds),
                  isSyncing: state.isSyncing,
                  onChanged: (isSubscribed) =>
                      notifier.setTopicGroupSubscription(
                        topics: interest.topics,
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
              style: AppTheme.bodyStyle(colors).copyWith(color: colors.danger),
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
        '$activeCount / $totalCount selected',
        style: AppTheme.labelStyle(colors),
      ),
    );
  }
}

class _NotificationInterestToggle extends StatelessWidget {
  const _NotificationInterestToggle({
    required this.interest,
    required this.isSubscribed,
    required this.isSyncing,
    required this.onChanged,
  });

  final _NotificationInterest interest;
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
      key: Key('notification_interest_${interest.key}'),
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.tightRadius,
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        children: [
          Expanded(
            child: PressableScale(
              key: Key('notification_interest_hit_${interest.key}'),
              onTap: isSyncing ? null : () => onChanged(!isSubscribed),
              scale: 0.98,
              child: Row(
                children: [
                  _InterestIcon(isSubscribed: isSubscribed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KineticText(
                          interest.label,
                          maxLines: 2,
                          style: AppTheme.titleStyle(colors).copyWith(
                            color: foreground,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        KineticText(
                          interest.description,
                          maxLines: 1,
                          uppercase: false,
                          style: AppTheme.bodyStyle(colors).copyWith(
                            color: foreground.withValues(alpha: 0.60),
                            fontSize: 12,
                          ),
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
            key: Key('notification_interest_toggle_${interest.key}'),
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

class _InterestIcon extends StatelessWidget {
  const _InterestIcon({required this.isSubscribed});

  final bool isSubscribed;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final foreground = isSubscribed ? colors.accent : colors.mutedForeground;
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
      child: Icon(
        isSubscribed
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
        color: foreground,
        size: 23,
      ),
    );
  }
}

class _NotificationInterest {
  const _NotificationInterest({
    required this.key,
    required this.label,
    required this.topics,
  });

  final String key;
  final String label;
  final List<NotificationTopic> topics;

  String get description {
    // A due date is not a price feed, so it should not borrow the wording of
    // one. "Receive zakat updates and alerts" says nothing about when.
    final isReminder = topics.every(
      (topic) => topic.kind == NotificationTopicKind.zakatDue,
    );
    if (!isReminder) return 'Receive ${label.toLowerCase()} updates and alerts.';
    // The row gives this one line before it ellipsises, so it has to be short.
    final leads = topics.map((topic) => topic.leadDays).toSet();
    final parts = <String>[
      if (leads.contains(7)) 'a week before it is due',
      if (leads.contains(0)) 'on the day',
    ];
    if (parts.isEmpty) return 'Reminders for upcoming zakat.';
    final sentence = parts.join(', and ');
    return '${sentence[0].toUpperCase()}${sentence.substring(1)}.';
  }

  bool isSelected(Set<String> subscribedTopicIds) {
    return topics.any((topic) => subscribedTopicIds.contains(topic.id));
  }

  static List<_NotificationInterest> fromTopics(
    List<NotificationTopic> topics,
  ) {
    final groupedTopics = <String, List<NotificationTopic>>{};
    final labels = <String, String>{};
    for (final topic in topics) {
      groupedTopics.putIfAbsent(topic.subjectKey, () => []).add(topic);
      labels.putIfAbsent(topic.subjectKey, () => topic.subjectLabel);
    }
    return groupedTopics.entries
        .map(
          (entry) => _NotificationInterest(
            key: entry.key,
            label: labels[entry.key] ?? entry.key,
            topics: List<NotificationTopic>.unmodifiable(entry.value),
          ),
        )
        .toList(growable: false);
  }
}
