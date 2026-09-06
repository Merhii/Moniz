import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/money_entry.dart';
import '../providers/display_currency_provider.dart';
import '../providers/metal_price_provider.dart';
import '../providers/money_entry_provider.dart';
import '../services/currency_converter.dart';
import '../services/money_ledger.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';
import 'money_capture_sheet.dart';

/// The surface the app opens on. A wallet that opens on a total-wealth screen
/// is telling you it is not really a wallet.
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final entries = ref.watch(moneyEntryProvider);
    final categories = ref.watch(moneyCategoryProvider);
    final displayCurrency = ref.watch(displayCurrencyProvider);
    final prices = ref.watch(metalPriceProvider).snapshot;

    final now = DateTime.now();
    final todaysEntries = MoneyLedger.newestFirst(
      MoneyLedger.inRange(entries, DateRange.day(now)),
    );
    final today = MoneyLedger.totals(
      todaysEntries,
      displayCurrency: displayCurrency,
      prices: prices,
    );
    final month = MoneyLedger.totals(
      MoneyLedger.inRange(entries, DateRange.month(now)),
      displayCurrency: displayCurrency,
      prices: prices,
    );
    final labels = {for (final category in categories) category.id: category.label};

    return CustomScrollView(
      key: const Key('today_scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: _SpendHero(today: today, month: month),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: BrutalistButton(
              key: const Key('add_money_entry'),
              label: 'Add entry',
              tone: BrutalistButtonTone.primary,
              expand: true,
              onPressed: () => captureMoneyEntry(context, ref),
            ),
          ),
        ),
        if (todaysEntries.isEmpty)
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
                    'Nothing logged today',
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
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            sliver: SliverList.separated(
              itemCount: todaysEntries.length,
              itemBuilder: (context, index) => _EntryRow(
                entry: todaysEntries[index],
                categoryLabel: labels[todaysEntries[index].categoryId],
              ),
              separatorBuilder: (context, index) => Divider(
                height: 24,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.15),
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens capture and stores whatever comes back. Returns the saved entry so a
/// caller can react to it.
Future<MoneyEntry?> captureMoneyEntry(
  BuildContext context,
  WidgetRef ref, {
  MoneyEntry? entry,
}) async {
  // Zero-duration like the app's other pushes: capture is on a three-tap
  // budget and a transition is time spent looking at nothing.
  final result = await Navigator.of(context).push<MoneyEntry>(
    PageRouteBuilder<MoneyEntry>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => MoneyCaptureSheet(entry: entry),
      fullscreenDialog: true,
    ),
  );
  if (result == null) return null;

  final notifier = ref.read(moneyEntryProvider.notifier);
  if (entry == null) {
    await notifier.addEntry(result);
  } else {
    await notifier.updateEntry(result);
  }
  return result;
}

class _SpendHero extends StatelessWidget {
  const _SpendHero({required this.today, required this.month});

  final MoneyTotals today;
  final MoneyTotals month;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          KineticText(
            'Spent today',
            style: AppTheme.labelStyle(
              colors,
            ).copyWith(fontSize: 12, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: KineticNumber(
              CurrencyConverter.formatMoney(today.expense, today.currency),
              key: const Key('today_spend_total'),
              fontSize: 48,
              color: colors.foreground,
              currency: today.currency,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MiniStat(
                label: 'In today',
                value: CurrencyConverter.formatMoney(
                  today.income,
                  today.currency,
                ),
              ),
              const SizedBox(width: 28),
              _MiniStat(
                key: const Key('month_spend_total'),
                label: 'This month',
                value: CurrencyConverter.formatMoney(
                  month.expense,
                  month.currency,
                ),
              ),
            ],
          ),
          if (!month.isComplete) ...[
            const SizedBox(height: 12),
            KineticText(
              month.excludedEntryCount == 1
                  ? '1 entry is in a currency with no exchange rate and is '
                        'left out of these totals.'
                  : '${month.excludedEntryCount} entries are in a currency '
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      children: [
        KineticText(
          label,
          muted: true,
          style: AppTheme.labelStyle(colors).copyWith(fontSize: 10),
        ),
        const SizedBox(height: 4),
        KineticText(
          value,
          uppercase: false,
          style: AppTheme.bodyStyle(
            colors,
          ).copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry, this.categoryLabel});

  final MoneyEntry entry;
  final String? categoryLabel;

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
                  if (entry.note != null && entry.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    KineticText(
                      entry.note!,
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
