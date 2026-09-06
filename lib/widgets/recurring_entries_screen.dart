import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/money_entry.dart';
import '../models/recurring_entry.dart';
import '../providers/money_entry_provider.dart';
import '../providers/recurring_entry_provider.dart';
import '../services/currency_converter.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';
import 'recurring_entry_form.dart';

/// The things the owner has said will keep happening.
class RecurringEntriesScreen extends ConsumerWidget {
  const RecurringEntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final rules = ref.watch(recurringEntryProvider);
    final labels = {
      for (final category in ref.watch(moneyCategoryProvider))
        category.id: category.label,
    };

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        leading: IconButton(
          key: const Key('close_recurring_list'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: KineticText(
          'Repeating',
          style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
        ),
      ),
      body: DecoratedBox(
        decoration: AppTheme.brandBackground(colors),
        child: SafeArea(
          child: ListView(
            key: const Key('recurring_list_scroll'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              KineticText(
                'Entries that create themselves. Nothing is created before the '
                'start date or past today, so a repeat can never put money you '
                'have not received into your totals.',
                muted: true,
                uppercase: false,
                style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
              ),
              const SizedBox(height: 18),
              BrutalistButton(
                key: const Key('add_recurring_entry'),
                label: 'Add repeat',
                tone: BrutalistButtonTone.primary,
                expand: true,
                onPressed: () => editRecurringEntry(context, ref),
              ),
              const SizedBox(height: 20),
              if (rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_repeat_outlined,
                        size: 40,
                        color: colors.accent,
                      ),
                      const SizedBox(height: 14),
                      KineticText(
                        'Nothing repeats yet',
                        key: const Key('recurring_empty_title'),
                        align: TextAlign.center,
                        style: AppTheme.titleStyle(
                          colors,
                        ).copyWith(fontSize: 19),
                      ),
                      const SizedBox(height: 8),
                      KineticText(
                        'Salary on the 25th, rent on the 1st — the entries '
                        'that are most tedious to type are the most '
                        'predictable.',
                        align: TextAlign.center,
                        muted: true,
                        uppercase: false,
                        style: AppTheme.bodyStyle(
                          colors,
                        ).copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                )
              else
                for (final rule in rules) ...[
                  _RuleTile(rule: rule, categoryLabel: labels[rule.categoryId]),
                  Divider(
                    height: 28,
                    thickness: 1,
                    color: colors.border.withValues(alpha: 0.15),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the rule form and stores whatever comes back.
Future<void> editRecurringEntry(
  BuildContext context,
  WidgetRef ref, {
  RecurringEntry? rule,
}) async {
  final result = await Navigator.of(context).push<RecurringFormResult>(
    PageRouteBuilder<RecurringFormResult>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => RecurringEntryForm(rule: rule),
      fullscreenDialog: true,
    ),
  );
  if (result == null) return;

  final notifier = ref.read(recurringEntryProvider.notifier);
  if (result.isDeleted) {
    await notifier.remove(result.rule.id);
    return;
  }
  await notifier.upsert(result.rule);
  // A rule that started last month owes those entries now, not on the next
  // launch.
  await applyDueRecurrences(ref);
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.rule, this.categoryLabel});

  final RecurringEntry rule;
  final String? categoryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final amount = CurrencyConverter.formatMoney(rule.amount, rule.currency);
    return InkWell(
      key: Key('recurring_rule_${rule.id}'),
      onTap: () => editRecurringEntry(context, ref, rule: rule),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: KineticText(
                    categoryLabel ?? 'Uncategorised',
                    uppercase: false,
                    style: AppTheme.bodyStyle(colors).copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: rule.isPaused
                          ? colors.mutedForeground
                          : colors.foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                KineticText(
                  '${rule.direction == MoneyDirection.income ? '+' : '−'}$amount',
                  key: Key('recurring_amount_${rule.id}'),
                  uppercase: false,
                  style: AppTheme.bodyStyle(colors).copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: rule.isPaused
                        ? colors.mutedForeground
                        : (rule.direction == MoneyDirection.income
                              ? colors.accent
                              : colors.foreground),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: KineticText(
                    rule.isPaused
                        ? '${rule.scheduleLabel} · Paused'
                        : rule.scheduleLabel,
                    key: Key('recurring_schedule_${rule.id}'),
                    muted: true,
                    uppercase: false,
                    style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                  ),
                ),
                TextButton(
                  key: Key('recurring_pause_${rule.id}'),
                  onPressed: () async {
                    await ref
                        .read(recurringEntryProvider.notifier)
                        .setPaused(rule.id, !rule.isPaused);
                    // Resuming catches up on what was missed while paused.
                    if (rule.isPaused) await applyDueRecurrences(ref);
                  },
                  child: KineticText(
                    rule.isPaused ? 'Resume' : 'Pause',
                    uppercase: false,
                    style: AppTheme.bodyStyle(
                      colors,
                    ).copyWith(color: colors.accent, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
