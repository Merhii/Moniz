import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/portfolio_snapshot.dart';
import '../providers/asset_provider.dart';
import '../providers/portfolio_snapshot_provider.dart';
import '../services/transaction_history_service.dart';

class TransactionHistoryScreen extends ConsumerWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(assetProvider);
    final snapshots = ref.watch(portfolioSnapshotProvider);
    final events = TransactionHistoryService.eventsFor(assets);
    final profitLoss = TransactionHistoryService.realizedProfitLossFor(assets);

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction History')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Realized Profit / Loss',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (profitLoss.isEmpty)
            const Text(
              'No completed buy/sell transactions with prices yet.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...profitLoss.map(_ProfitLossTile.new),
          const SizedBox(height: 22),
          Text('Timeline', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (events.isEmpty)
            const Text(
              'Add holding start or sold dates to build your timeline.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...events.map(_EventTile.new),
          const SizedBox(height: 22),
          Text(
            'Net Worth Snapshots',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (snapshots.isEmpty)
            const Text(
              'Save a snapshot from Wealth Breakdown to begin tracking history.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...snapshots.map(_SnapshotTile.new),
        ],
      ),
    );
  }
}

class _ProfitLossTile extends StatelessWidget {
  const _ProfitLossTile(this.item);

  final RealizedProfitLoss item;

  @override
  Widget build(BuildContext context) {
    final isGain = item.amount >= 0;
    return Card(
      child: ListTile(
        title: Text(item.asset.type.label),
        subtitle: const Text('Realized result'),
        trailing: Text(
          '${isGain ? '+' : '-'}${item.currency} '
          '${item.amount.abs().toStringAsFixed(2)}',
          style: TextStyle(
            color: isGain ? const Color(0xFF22C55E) : Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.event);

  final TransactionEvent event;

  @override
  Widget build(BuildContext context) {
    final isSale = event.type == TransactionEventType.sold;
    final price = event.price == null
        ? ''
        : ' | ${event.asset.currency} ${event.price!.toStringAsFixed(2)}';
    return Card(
      child: ListTile(
        leading: Icon(isSale ? Icons.sell_outlined : Icons.add_circle_outline),
        title: Text(
          '${isSale ? 'Sold' : 'Acquired'} ${event.asset.type.label}',
        ),
        subtitle: Text('${_formatDate(event.date)}$price'),
        trailing: Text('${event.asset.amount} ${event.asset.unit}'),
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile(this.snapshot);

  final PortfolioSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('\$${snapshot.totalUsd.toStringAsFixed(2)}'),
        subtitle: Text(_formatDateTime(snapshot.capturedAt)),
        trailing: Text(
          'Gold \$${snapshot.goldUsd.toStringAsFixed(0)}\n'
          'Cash \$${(snapshot.cashUsd + snapshot.bankSavingsUsd).toStringAsFixed(0)}',
          textAlign: TextAlign.end,
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
