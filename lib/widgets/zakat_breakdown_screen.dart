import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/zakat_settings.dart';
import '../providers/asset_provider.dart';
import '../providers/metal_price_provider.dart';
import '../providers/zakat_provider.dart';
import '../services/zakat_engine.dart';

class ZakatBreakdownScreen extends ConsumerWidget {
  const ZakatBreakdownScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(zakatProvider);
    final notifier = ref.read(zakatProvider.notifier);
    final result = ZakatEngine.calculate(
      assets: ref.watch(assetProvider),
      prices: ref.watch(metalPriceProvider).snapshot,
      settings: settings,
      payments: notifier.payments,
      today: DateTime.now(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Zakat Breakdown')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ZakatSettingsCard(settings: settings),
          const SizedBox(height: 16),
          _CalculationCard(result: result),
          const SizedBox(height: 16),
          Text('Holdings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (!result.canCalculate)
            const Text('Refresh metal prices from the dashboard first.')
          else if (result.assessments.isEmpty)
            const Text('No assets added yet.')
          else
            ...result.assessments.map(_AssessmentTile.new),
        ],
      ),
    );
  }
}

class _ZakatSettingsCard extends ConsumerWidget {
  const _ZakatSettingsCard({required this.settings});

  final ZakatSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(zakatProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Calculation Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ZakatScheduleMode>(
              key: const Key('zakat_schedule_mode'),
              initialValue: settings.scheduleMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: ZakatScheduleMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(),
              onChanged: (mode) {
                if (mode != null) notifier.setScheduleMode(mode);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<NisabStandard>(
              key: const Key('nisab_standard'),
              initialValue: settings.nisabStandard,
              decoration: const InputDecoration(labelText: 'Nisab Standard'),
              items: NisabStandard.values
                  .map(
                    (standard) => DropdownMenuItem(
                      value: standard,
                      child: Text(standard.label),
                    ),
                  )
                  .toList(),
              onChanged: (standard) {
                if (standard != null) notifier.setNisabStandard(standard);
              },
            ),
            if (settings.scheduleMode == ZakatScheduleMode.ramadanAnnual) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Next Ramadan payment date'),
                subtitle: Text(
                  settings.nextRamadanDueDate == null
                      ? 'Not selected'
                      : _formatDate(settings.nextRamadanDueDate!),
                ),
                trailing: TextButton(
                  key: const Key('select_ramadan_due_date'),
                  onPressed: () =>
                      _selectRamadanDate(context, notifier, settings),
                  child: const Text('Select'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              settings.scheduleMode == ZakatScheduleMode.ramadanAnnual
                  ? 'On your Ramadan date, all active valued holdings are assessed once.'
                  : 'Check monthly; only holdings past one lunar year and not already paid this cycle are assessed.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectRamadanDate(
    BuildContext context,
    ZakatNotifier notifier,
    ZakatSettings settings,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: settings.nextRamadanDueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) await notifier.setRamadanDueDate(date);
  }
}

class _CalculationCard extends ConsumerWidget {
  const _CalculationCard({required this.result});

  final ZakatResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount Due', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '\$${result.amountDueUsd.toStringAsFixed(2)}',
              key: const Key('zakat_amount_due'),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Eligible wealth: \$${result.eligibleWealthUsd.toStringAsFixed(2)}',
            ),
            Text(
              result.nisabThresholdUsd == null
                  ? 'Nisab: awaiting live prices'
                  : 'Nisab (${result.settings.nisabStandard.label}): '
                        '\$${result.nisabThresholdUsd!.toStringAsFixed(2)}',
            ),
            if (result.message != null) ...[
              const SizedBox(height: 8),
              Text(result.message!, style: const TextStyle(color: Colors.grey)),
            ],
            if (result.hasPaymentDue) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                key: const Key('mark_zakat_paid'),
                onPressed: () async {
                  await ref
                      .read(zakatProvider.notifier)
                      .recordPayment(result, DateTime.now());
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Zakat payment recorded.')),
                    );
                  }
                },
                child: const Text('Mark As Paid'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile(this.assessment);

  final ZakatAssetAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final value = assessment.valueUsd == null
        ? 'Not valued'
        : '\$${assessment.valueUsd!.toStringAsFixed(2)}';
    final status = assessment.isIncluded
        ? 'Included in amount due'
        : assessment.exclusionReason ?? 'Excluded';
    return Card(
      child: ListTile(
        title: Text(assessment.asset.type.label),
        subtitle: Text(status),
        trailing: Text(value),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
