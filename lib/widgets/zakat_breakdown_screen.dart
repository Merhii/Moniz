import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/zakat_settings.dart';
import '../providers/asset_provider.dart';
import '../providers/metal_price_provider.dart';
import '../providers/zakat_provider.dart';
import '../services/currency_converter.dart';
import '../services/zakat_engine.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

class ZakatBreakdownScreen extends ConsumerWidget {
  const ZakatBreakdownScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
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
      backgroundColor: colors.background,
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: colors.background,
        centerTitle: true,
        leading: IconButton(
          key: const Key('back_zakat_breakdown'),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: KineticText(
          'Zakat breakdown',
          style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
        ),
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(
                children: [
                  _ZakatSettingsBlock(settings: settings),
                  const SizedBox(height: 14),
                  _CalculationBlock(result: result),
                  const SizedBox(height: 14),
                  KineticText(
                    'Holdings',
                    style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 10),
                  if (!result.canCalculate)
                    const LedgerFrame(
                      child: KineticText(
                        'Refresh metal prices from Settings first.',
                      ),
                    )
                  else if (result.assessments.isEmpty)
                    const LedgerFrame(
                      child: KineticText('No assets added yet.'),
                    )
                  else
                    ...result.assessments.map(_AssessmentTile.new),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZakatSettingsBlock extends ConsumerWidget {
  const _ZakatSettingsBlock({required this.settings});

  final ZakatSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(zakatProvider.notifier);
    return LedgerFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KineticDropdown<ZakatScheduleMode>(
                  label: 'Schedule',
                  value: settings.scheduleMode,
                  items: ZakatScheduleMode.values,
                  onChanged: (mode) {
                    if (mode != null) notifier.setScheduleMode(mode);
                  },
                  itemLabelBuilder: (mode) => mode.label,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KineticDropdown<NisabStandard>(
                  label: 'Nisab Standard',
                  value: settings.nisabStandard,
                  items: NisabStandard.values,
                  onChanged: (standard) {
                    if (standard != null) notifier.setNisabStandard(standard);
                  },
                  itemLabelBuilder: (standard) => standard.label,
                ),
              ),
            ],
          ),
          if (settings.scheduleMode == ZakatScheduleMode.ramadanAnnual) ...[
            const SizedBox(height: 16),
            KineticDatePickerTile(
              key: const Key('select_ramadan_due_date'),
              label: 'Next Ramadan',
              value: settings.nextRamadanDueDate == null
                  ? 'Select date'
                  : _formatDate(settings.nextRamadanDueDate!),
              selected: settings.nextRamadanDueDate != null,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: settings.nextRamadanDueDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date != null) await notifier.setRamadanDueDate(date);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CalculationBlock extends ConsumerWidget {
  const _CalculationBlock({required this.result});

  final ZakatResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    return LedgerFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText('Amount due', style: AppTheme.labelStyle(colors)),
          const SizedBox(height: 10),
          KineticNumber(
            _formatMoney(result.amountDueUsd),
            key: const Key('zakat_amount_due'),
            fontSize: 48,
            currency: CurrencyConverter.defaultCurrency,
          ),
          const SizedBox(height: 10),
          KineticText(
            'Eligible wealth: ${_formatMoney(result.eligibleWealthUsd)}',
          ),
          KineticText(
            result.nisabThresholdUsd == null
                ? 'Nisab: awaiting live prices'
                : 'Nisab (${result.settings.nisabStandard.label}): '
                      '${_formatMoney(result.nisabThresholdUsd!)}',
          ),
          if (result.message != null) ...[
            const SizedBox(height: 8),
            KineticText(result.message!, muted: true, uppercase: false),
          ],
          if (result.hasPaymentDue) ...[
            const SizedBox(height: 12),
            BrutalistButton(
              key: const Key('mark_zakat_paid'),
              label: 'Mark as paid',
              tone: BrutalistButtonTone.primary,
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
            ),
          ],
        ],
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile(this.assessment);

  final ZakatAssetAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final value = assessment.valueUsd == null
        ? 'Not valued'
        : _formatMoney(assessment.valueUsd!);
    final status = assessment.isIncluded
        ? 'Included in amount due'
        : assessment.exclusionReason ?? 'Excluded';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LedgerFrame(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KineticText(
                    assessment.asset.type.label,
                    style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 5),
                  KineticText(status, muted: !assessment.isIncluded),
                ],
              ),
            ),
            KineticText(value),
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

String _formatMoney(double value) {
  return CurrencyConverter.formatMoney(
    value,
    CurrencyConverter.defaultCurrency,
  );
}
