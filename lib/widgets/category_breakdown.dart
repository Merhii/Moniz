import 'package:flutter/material.dart';

import '../services/currency_converter.dart';
import '../services/money_ledger.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

/// Where the money went, largest first.
///
/// Proportional bars rather than a pie: the question is "what is taking most
/// of it", which is a comparison of lengths, and lengths are easier to compare
/// than angles. It also needs no charting dependency — the bars are just
/// widths.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({
    super.key,
    required this.totals,
    required this.labels,
    required this.currency,
  });

  final List<CategoryTotal> totals;
  final Map<String, String> labels;
  final String currency;

  static const _maxRows = 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    if (totals.isEmpty) return const SizedBox.shrink();

    final largest = totals.first.amount;
    final shown = totals.take(_maxRows).toList();
    final remainder = totals.skip(_maxRows);
    final remainderTotal = remainder.fold<double>(
      0,
      (sum, total) => sum + total.amount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KineticText(
          'Where it went',
          key: const Key('category_breakdown_title'),
          style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
        ),
        const SizedBox(height: 14),
        for (final total in shown) ...[
          _BreakdownRow(
            label: labels[total.categoryId] ?? 'Uncategorised',
            amount: total.amount,
            fraction: largest == 0 ? 0 : total.amount / largest,
            currency: currency,
            rowKey: Key('breakdown_${total.categoryId ?? 'none'}'),
          ),
          const SizedBox(height: 12),
        ],
        if (remainderTotal > 0)
          KineticText(
            '${remainder.length} more, '
            '${CurrencyConverter.formatMoney(remainderTotal, currency)}',
            key: const Key('breakdown_remainder'),
            muted: true,
            uppercase: false,
            style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
          ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.amount,
    required this.fraction,
    required this.currency,
    required this.rowKey,
  });

  final String label;
  final double amount;
  final double fraction;
  final String currency;
  final Key rowKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      key: rowKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: KineticText(
                label,
                uppercase: false,
                maxLines: 1,
                style: AppTheme.bodyStyle(
                  colors,
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            KineticText(
              CurrencyConverter.formatMoney(amount, currency),
              uppercase: false,
              style: AppTheme.bodyStyle(
                colors,
              ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppTheme.pillRadius,
          child: Stack(
            children: [
              Container(
                height: 8,
                color: colors.foreground.withValues(alpha: 0.06),
              ),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.02, 1),
                child: Container(height: 8, color: colors.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Income against expense for the selected window, and what is left.
class MoneyFlowSummary extends StatelessWidget {
  const MoneyFlowSummary({super.key, required this.totals});

  final MoneyTotals totals;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final net = totals.net;
    return Row(
      children: [
        Expanded(
          child: _FlowStat(
            label: 'In',
            value: CurrencyConverter.formatMoney(totals.income, totals.currency),
            valueKey: const Key('flow_income'),
          ),
        ),
        Expanded(
          child: _FlowStat(
            label: 'Out',
            value: CurrencyConverter.formatMoney(
              totals.expense,
              totals.currency,
            ),
            valueKey: const Key('flow_expense'),
          ),
        ),
        Expanded(
          child: _FlowStat(
            label: 'Left',
            value:
                '${net < 0 ? '−' : ''}'
                '${CurrencyConverter.formatMoney(net.abs(), totals.currency)}',
            valueKey: const Key('flow_net'),
            // Spending more than came in is worth seeing, not worth alarming
            // about — it is normal in a month you were paid in the last one.
            color: net < 0 ? colors.mutedForeground : colors.accent,
          ),
        ),
      ],
    );
  }
}

class _FlowStat extends StatelessWidget {
  const _FlowStat({
    required this.label,
    required this.value,
    required this.valueKey,
    this.color,
  });

  final String label;
  final String value;
  final Key valueKey;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KineticText(
          label,
          muted: true,
          style: AppTheme.labelStyle(colors).copyWith(fontSize: 10),
        ),
        const SizedBox(height: 4),
        KineticText(
          value,
          key: valueKey,
          uppercase: false,
          style: AppTheme.bodyStyle(colors).copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color ?? colors.foreground,
          ),
        ),
      ],
    );
  }
}
