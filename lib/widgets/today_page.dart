import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/money_entry.dart';
import '../providers/display_currency_provider.dart';
import '../providers/metal_price_provider.dart';
import '../providers/money_entry_provider.dart';
import '../providers/recurring_entry_provider.dart';
import '../services/currency_converter.dart';
import '../services/money_ledger.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';
import 'category_breakdown.dart';
import 'money_capture_sheet.dart';
import 'recurring_entries_screen.dart';
import 'spending_period.dart';

/// The surface the app opens on. A wallet that opens on a total-wealth screen
/// is telling you it is not really a wallet.
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  var _period = SpendingPeriod.today;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final entries = ref.watch(moneyEntryProvider);
    final categories = ref.watch(moneyCategoryProvider);
    final displayCurrency = ref.watch(displayCurrencyProvider);
    final prices = ref.watch(metalPriceProvider).snapshot;

    final now = DateTime.now();
    final periodEntries = MoneyLedger.newestFirst(
      MoneyLedger.inRange(entries, _period.rangeAt(now)),
    );
    final totals = MoneyLedger.totals(
      periodEntries,
      displayCurrency: displayCurrency,
      prices: prices,
    );
    final wider = _period.widerPeriod;
    final widerTotals = wider == null
        ? null
        : MoneyLedger.totals(
            MoneyLedger.inRange(entries, wider.rangeAt(now)),
            displayCurrency: displayCurrency,
            prices: prices,
          );
    final activeRepeats = ref
        .watch(recurringEntryProvider)
        .where((rule) => !rule.isPaused)
        .length;
    final byCategory = MoneyLedger.byCategory(
      periodEntries,
      direction: MoneyDirection.expense,
      displayCurrency: displayCurrency,
      prices: prices,
    );
    final labels = {for (final category in categories) category.id: category.label};

    return CustomScrollView(
      key: const Key('today_scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: _SpendHero(
            period: _period,
            totals: totals,
            wider: wider,
            widerTotals: widerTotals,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _PeriodSelector(
              period: _period,
              onChanged: (period) => setState(() => _period = period),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: BrutalistButton(
              key: const Key('add_money_entry'),
              label: 'Add entry',
              tone: BrutalistButtonTone.primary,
              expand: true,
              onPressed: () => captureMoneyEntry(context, ref),
            ),
          ),
        ),
        // Quiet, and directly under the primary action rather than competing
        // with it. Somebody who just typed rent for the third month should be
        // able to find this without going hunting in Settings.
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('open_recurring_entries'),
              onPressed: () => Navigator.of(context).push<void>(
                PageRouteBuilder<void>(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  pageBuilder: (_, _, _) => const RecurringEntriesScreen(),
                ),
              ),
              child: KineticText(
                activeRepeats == 0
                    ? 'Set up something that repeats'
                    : '$activeRepeats repeating',
                uppercase: false,
                style: AppTheme.bodyStyle(
                  colors,
                ).copyWith(color: colors.accent, fontSize: 13),
              ),
            ),
          ),
        ),
        if (periodEntries.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 40,
                    color: colors.accent,
                  ),
                  const SizedBox(height: 14),
                  KineticText(
                    _period.emptyLabel,
                    key: const Key('today_empty_title'),
                    align: TextAlign.center,
                    style: AppTheme.titleStyle(colors).copyWith(fontSize: 19),
                  ),
                  const SizedBox(height: 8),
                  KineticText(
                    'Add what you spent or earned and it counts towards your '
                    'wealth and your zakat.',
                    align: TextAlign.center,
                    muted: true,
                    uppercase: false,
                    style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: MoneyFlowSummary(totals: totals),
            ),
          ),
          if (byCategory.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: CategoryBreakdown(
                  totals: byCategory,
                  labels: labels,
                  currency: totals.currency,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: KineticText(
                'Entries',
                style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList.separated(
              itemCount: periodEntries.length,
              itemBuilder: (context, index) => _EntryRow(
                entry: periodEntries[index],
                categoryLabel: labels[periodEntries[index].categoryId],
                showsDate: _period != SpendingPeriod.today,
              ),
              separatorBuilder: (context, index) => Divider(
                height: 24,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.15),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Opens capture and stores whatever comes back. Returns the saved entry so a
/// caller can react to it.
Future<MoneyCaptureResult?> captureMoneyEntry(
  BuildContext context,
  WidgetRef ref, {
  MoneyEntry? entry,
}) async {
  // Zero-duration like the app's other pushes: capture is on a three-tap
  // budget and a transition is time spent looking at nothing.
  final result = await Navigator.of(context).push<MoneyCaptureResult>(
    PageRouteBuilder<MoneyCaptureResult>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => MoneyCaptureSheet(entry: entry),
      fullscreenDialog: true,
    ),
  );
  if (result == null) return null;

  final notifier = ref.read(moneyEntryProvider.notifier);
  if (result.isDeleted) {
    await notifier.removeEntry(result.entry.id);
  } else if (entry == null) {
    await notifier.addEntry(result.entry);
  } else {
    await notifier.updateEntry(result.entry);
  }
  return result;
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onChanged});

  final SpendingPeriod period;
  final ValueChanged<SpendingPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.foreground.withValues(alpha: 0.04),
        borderRadius: AppTheme.pillRadius,
        border: Border.all(color: colors.border.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          for (final option in SpendingPeriod.values)
            Expanded(
              child: GestureDetector(
                key: Key('spending_period_${option.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(option),
                child: AnimatedContainer(
                  duration: AppTheme.fast,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: period == option
                        ? colors.accent
                        : Colors.transparent,
                    borderRadius: AppTheme.pillRadius,
                  ),
                  child: Center(
                    child: KineticText(
                      option.label,
                      style: AppTheme.labelStyle(colors).copyWith(
                        color: period == option
                            ? colors.accentForeground
                            : colors.mutedForeground,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpendHero extends StatelessWidget {
  const _SpendHero({
    required this.period,
    required this.totals,
    required this.wider,
    required this.widerTotals,
  });

  final SpendingPeriod period;
  final MoneyTotals totals;
  final SpendingPeriod? wider;
  final MoneyTotals? widerTotals;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final widerTotal = widerTotals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          KineticText(
            period.spentLabel,
            key: const Key('today_spend_label'),
            style: AppTheme.labelStyle(
              colors,
            ).copyWith(fontSize: 12, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: KineticNumber(
              CurrencyConverter.formatMoney(totals.expense, totals.currency),
              key: const Key('today_spend_total'),
              fontSize: 48,
              color: colors.foreground,
              currency: totals.currency,
            ),
          ),
          if (widerTotal != null && wider != null) ...[
            const SizedBox(height: 10),
            KineticText(
              'of ${CurrencyConverter.formatMoney(widerTotal.expense, widerTotal.currency)} '
              'this ${wider!.label.toLowerCase()}',
              key: const Key('today_wider_total'),
              muted: true,
              uppercase: false,
              style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
            ),
          ],
          if (!totals.isComplete) ...[
            const SizedBox(height: 12),
            KineticText(
              totals.excludedEntryCount == 1
                  ? '1 entry is in a currency with no exchange rate and is '
                        'left out of these totals.'
                  : '${totals.excludedEntryCount} entries are in a currency '
                        'with no exchange rate and are left out of these '
                        'totals.',
              key: const Key('today_excluded_note'),
              align: TextAlign.center,
              muted: true,
              uppercase: false,
              style: AppTheme.bodyStyle(colors).copyWith(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.entry,
    this.categoryLabel,
    this.showsDate = false,
  });

  final MoneyEntry entry;
  final String? categoryLabel;

  /// Only outside the Today window, where "when" stops being obvious.
  final bool showsDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final amount = CurrencyConverter.formatMoney(entry.amount, entry.currency);
    return InkWell(
      key: Key('money_entry_${entry.id}'),
      onTap: () => captureMoneyEntry(context, ref, entry: entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KineticText(
                    categoryLabel ?? 'Uncategorised',
                    uppercase: false,
                    style: AppTheme.bodyStyle(
                      colors,
                    ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  if (showsDate || (entry.note?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 4),
                    KineticText(
                      [
                        if (showsDate) _shortDate(entry.happenedAt),
                        if (entry.note?.isNotEmpty ?? false) entry.note!,
                      ].join(' · '),
                      muted: true,
                      uppercase: false,
                      style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            KineticText(
              '${entry.isIncome ? '+' : '−'}$amount',
              key: Key('money_entry_amount_${entry.id}'),
              uppercase: false,
              style: AppTheme.bodyStyle(colors).copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: entry.isIncome ? colors.accent : colors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortDate(DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[date.weekday - 1]} ${date.day}';
}
