import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/zakat_provider.dart';
import '../services/currency_converter.dart';
import '../services/zakat_engine.dart';
import '../ui/kinetic/kinetic_widgets.dart';

/// Records a zakat payment, after asking.
///
/// Shared by the Zakat page and the breakdown screen, which previously each
/// carried their own copy of this button and its handler.
class ZakatMarkPaidButton extends ConsumerWidget {
  const ZakatMarkPaidButton({super.key, required this.result});

  final ZakatResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BrutalistButton(
      key: const Key('mark_zakat_paid'),
      label: 'Mark as paid',
      tone: BrutalistButtonTone.primary,
      onPressed: () => _confirmAndRecord(context, ref),
    );
  }

  Future<void> _confirmAndRecord(BuildContext context, WidgetRef ref) async {
    final amount = CurrencyConverter.formatMoney(
      result.amountDueUsd,
      CurrencyConverter.defaultCurrency,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record this zakat payment?'),
        content: Text(
          'This records $amount as paid and starts a new lunar year for the '
          'holdings it covers, so they will not be assessed again until it '
          'passes. It cannot be undone from the app.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel_zakat_payment'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm_zakat_payment'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(zakatProvider.notifier)
        .recordPayment(result, DateTime.now());
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Zakat payment recorded.')));
  }
}
