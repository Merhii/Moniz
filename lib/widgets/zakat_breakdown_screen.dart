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
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.heroSurface(colors),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BrutalistButton(
                        label: 'BACK',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 18),
                      KineticText(
                        'ZAKAT BREAKDOWN',
                        style: AppTheme.displayStyle(
                          colors,
                        ).copyWith(fontSize: 52, color: colors.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(
                children: [
                  _ZakatSettingsBlock(settings: settings),
                  const SizedBox(height: 14),
                  _CalculationBlock(result: result),
                  const SizedBox(height: 14),
                  KineticText(
                    'HOLDINGS',
                    style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
                  ),
                  const SizedBox(height: 10),
                  if (!result.canCalculate)
                    const LedgerFrame(
                      child: KineticText(
                        'REFRESH METAL PRICES FROM SYSTEM FIRST.',
                      ),
                    )
                  else if (result.assessments.isEmpty)
                    const LedgerFrame(
                      child: KineticText('NO ASSETS ADDED YET.'),
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
    final colors = context.kinetic;
    final notifier = ref.read(zakatProvider.notifier);
    return LedgerFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText(
            'CALCULATION SETTINGS',
            style: AppTheme.labelStyle(colors),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ZakatScheduleMode.values
                .map(
                  (mode) => FilterBlock(
                    key: Key('zakat_schedule_${mode.name}'),
                    label: mode.label,
                    selected: settings.scheduleMode == mode,
                    onTap: () => notifier.setScheduleMode(mode),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: NisabStandard.values
                .map(
                  (standard) => FilterBlock(
                    key: Key('nisab_${standard.name}'),
                    label: standard.label,
                    selected: settings.nisabStandard == standard,
                    onTap: () => notifier.setNisabStandard(standard),
                  ),
                )
                .toList(),
          ),
          if (settings.scheduleMode == ZakatScheduleMode.ramadanAnnual) ...[
            const SizedBox(height: 14),
            BrutalistButton(
              key: const Key('select_ramadan_due_date'),
              label: settings.nextRamadanDueDate == null
                  ? 'SELECT RAMADAN DATE'
                  : _formatDate(settings.nextRamadanDueDate!),
              tone: BrutalistButtonTone.primary,
              onPressed: () async {
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
          KineticText('AMOUNT DUE', style: AppTheme.labelStyle(colors)),
          const SizedBox(height: 10),
          KineticNumber(
            _formatMoney(result.amountDueUsd),
            key: const Key('zakat_amount_due'),
            fontSize: 64,
          ),
          const SizedBox(height: 10),
          KineticText(
            'ELIGIBLE WEALTH: ${_formatMoney(result.eligibleWealthUsd)}',
          ),
          KineticText(
            result.nisabThresholdUsd == null
                ? 'NISAB: AWAITING LIVE PRICES'
                : 'NISAB (${result.settings.nisabStandard.label}): '
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
              label: 'MARK AS PAID',
              tone: BrutalistButtonTone.primary,
              onPressed: () async {
                await ref
                    .read(zakatProvider.notifier)
                    .recordPayment(result, DateTime.now());
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ZAKAT PAYMENT RECORDED.')),
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
        ? 'NOT VALUED'
        : _formatMoney(assessment.valueUsd!);
    final status = assessment.isIncluded
        ? 'INCLUDED IN AMOUNT DUE'
        : assessment.exclusionReason ?? 'EXCLUDED';
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
