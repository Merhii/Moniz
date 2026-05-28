import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/portfolio_snapshot.dart';
import '../providers/asset_provider.dart';
import '../providers/metal_price_provider.dart';
import '../providers/portfolio_snapshot_provider.dart';
import '../services/position_performance.dart';
import '../services/transaction_history_service.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

class TransactionHistoryScreen extends ConsumerWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final assets = ref.watch(assetProvider);
    final snapshots = ref.watch(portfolioSnapshotProvider);
    final events = TransactionHistoryService.eventsFor(assets);
    final performance = PositionPerformance.calculate(
      assets,
      ref.watch(metalPriceProvider).snapshot,
    );

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.border, width: 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BrutalistButton(
                      label: 'BACK',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 18),
                    KineticText(
                      'TRANSACTION HISTORY',
                      style: AppTheme.displayStyle(colors).copyWith(
                        fontSize: 52,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(
                children: [
                  KineticText(
                    'PAID VS NOW',
                    style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
                  ),
                  const SizedBox(height: 10),
                  if (!performance.hasComparablePositions)
                    const LedgerFrame(
                      child: KineticText(
                        'ADD BOUGHT PRICES TO ACTIVE USD HOLDINGS TO COMPARE PAID VS CURRENT WORTH.',
                        muted: true,
                      ),
                    )
                  else
                    _PerformanceTile(performance),
                  const SizedBox(height: 22),
                  KineticText(
                    'TIMELINE',
                    style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
                  ),
                  const SizedBox(height: 10),
                  if (events.isEmpty)
                    const LedgerFrame(
                      child: KineticText(
                        'ADD HOLDING START OR SOLD DATES TO BUILD YOUR TIMELINE.',
                        muted: true,
                      ),
                    )
                  else
                    ...events.map(_EventTile.new),
                  const SizedBox(height: 22),
                  KineticText(
                    'NET WORTH SNAPSHOTS',
                    style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
                  ),
                  const SizedBox(height: 10),
                  if (snapshots.isEmpty)
                    const LedgerFrame(
                      child: KineticText(
                        'SAVE A SNAPSHOT FROM WEALTH TO BEGIN TRACKING HISTORY.',
                        muted: true,
                      ),
                    )
                  else
                    ...snapshots.map(_SnapshotTile.new),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceTile extends StatelessWidget {
  const _PerformanceTile(this.summary);

  final PositionPerformanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final change = summary.changeUsd;
    final isGain = change >= 0;
    return LedgerFrame(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: KineticText(
              'PAID \$${summary.paidUsd.toStringAsFixed(2)} / '
              'NOW \$${summary.currentUsd.toStringAsFixed(2)}',
              style: AppTheme.titleStyle(colors).copyWith(fontSize: 18),
            ),
          ),
          KineticText(
            '${isGain ? '+' : '-'}\$${change.abs().toStringAsFixed(2)}',
            style: AppTheme.labelStyle(colors).copyWith(
              color: isGain ? colors.profit : colors.loss,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.event);

  final TransactionEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final isSale = event.type == TransactionEventType.sold;
    final price = event.price == null
        ? 'NO PRICE'
        : '${event.asset.currency} ${event.price!.toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LedgerFrame(
        padding: const EdgeInsets.all(12),
        borderWidth: 1,
        child: Row(
          children: [
            Container(
              height: 44,
              width: 12,
              color: isSale ? colors.loss : colors.profit,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KineticText(
                    '${isSale ? 'Sold' : 'Acquired'} ${event.asset.type.label}',
                    style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  KineticText(
                    '${_formatDate(event.date)} / $price',
                    muted: true,
                  ),
                ],
              ),
            ),
            KineticText('${event.asset.amount} ${event.asset.unit}'),
          ],
        ),
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile(this.snapshot);

  final PortfolioSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LedgerFrame(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KineticNumber(
                    '\$${snapshot.totalUsd.toStringAsFixed(2)}',
                    fontSize: 28,
                  ),
                  const SizedBox(height: 4),
                  KineticText(
                    _formatDateTime(snapshot.capturedAt),
                    muted: true,
                  ),
                ],
              ),
            ),
            KineticText(
              'GOLD \$${snapshot.goldUsd.toStringAsFixed(0)}\n'
              'CASH \$${(snapshot.cashUsd + snapshot.bankSavingsUsd).toStringAsFixed(0)}',
              align: TextAlign.end,
              style: AppTheme.labelStyle(colors).copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _formatDateTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_formatDate(date)} $hour:$minute';
}
