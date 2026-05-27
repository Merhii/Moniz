import '../models/asset.dart';
import '../models/metal_price_snapshot.dart';
import '../models/zakat_settings.dart';

class ZakatAssetAssessment {
  const ZakatAssetAssessment({
    required this.asset,
    required this.valueUsd,
    required this.isIncluded,
    this.nextDueDate,
    this.exclusionReason,
  });

  final Asset asset;
  final double? valueUsd;
  final bool isIncluded;
  final DateTime? nextDueDate;
  final String? exclusionReason;
}

class ZakatResult {
  const ZakatResult({
    required this.settings,
    required this.assessments,
    required this.nisabThresholdUsd,
    required this.eligibleWealthUsd,
    required this.amountDueUsd,
    required this.canCalculate,
    required this.isScheduleDue,
    this.message,
  });

  final ZakatSettings settings;
  final List<ZakatAssetAssessment> assessments;
  final double? nisabThresholdUsd;
  final double eligibleWealthUsd;
  final double amountDueUsd;
  final bool canCalculate;
  final bool isScheduleDue;
  final String? message;

  bool get hasPaymentDue => canCalculate && amountDueUsd > 0;

  List<ZakatAssetAssessment> get includedAssessments =>
      assessments.where((item) => item.isIncluded).toList();
}

class ZakatEngine {
  static const _goldNisabGrams = 85.0;
  static const _silverNisabGrams = 612.36;
  static const _hawlDays = 354;

  static ZakatResult calculate({
    required List<Asset> assets,
    required MetalPriceSnapshot? prices,
    required ZakatSettings settings,
    required Map<String, ZakatPaymentRecord> payments,
    required DateTime today,
  }) {
    if (prices == null) {
      return ZakatResult(
        settings: settings,
        assessments: const [],
        nisabThresholdUsd: null,
        eligibleWealthUsd: 0,
        amountDueUsd: 0,
        canCalculate: false,
        isScheduleDue: false,
        message: 'Refresh prices to calculate the current nisab and zakat.',
      );
    }

    final nisabThresholdUsd = settings.nisabStandard == NisabStandard.gold
        ? prices.goldPerGramUsd * _goldNisabGrams
        : prices.silverPerGramUsd * _silverNisabGrams;
    final scheduleDue = _isScheduleDue(settings, today);
    final assessments = assets
        .map(
          (asset) => _assessAsset(
            asset: asset,
            prices: prices,
            settings: settings,
            payments: payments,
            today: today,
            scheduleDue: scheduleDue,
          ),
        )
        .toList();
    final eligibleWealthUsd = assessments
        .where((assessment) => assessment.isIncluded)
        .fold<double>(0, (sum, assessment) => sum + (assessment.valueUsd ?? 0));
    final amountDueUsd = eligibleWealthUsd >= nisabThresholdUsd
        ? eligibleWealthUsd * 0.025
        : 0.0;

    return ZakatResult(
      settings: settings,
      assessments: assessments,
      nisabThresholdUsd: nisabThresholdUsd,
      eligibleWealthUsd: eligibleWealthUsd,
      amountDueUsd: amountDueUsd,
      canCalculate: true,
      isScheduleDue: scheduleDue,
      message: _messageFor(
        settings: settings,
        scheduleDue: scheduleDue,
        eligibleWealthUsd: eligibleWealthUsd,
        nisabThresholdUsd: nisabThresholdUsd,
      ),
    );
  }

  static ZakatAssetAssessment _assessAsset({
    required Asset asset,
    required MetalPriceSnapshot prices,
    required ZakatSettings settings,
    required Map<String, ZakatPaymentRecord> payments,
    required DateTime today,
    required bool scheduleDue,
  }) {
    if (asset.isSold) {
      return ZakatAssetAssessment(
        asset: asset,
        valueUsd: null,
        isIncluded: false,
        exclusionReason: 'Sold asset',
      );
    }

    final valueUsd = _assetValueUsd(asset, prices);
    if (valueUsd == null) {
      return ZakatAssetAssessment(
        asset: asset,
        valueUsd: null,
        isIncluded: false,
        exclusionReason: 'Unsupported currency',
      );
    }

    if (settings.scheduleMode == ZakatScheduleMode.ramadanAnnual) {
      return ZakatAssetAssessment(
        asset: asset,
        valueUsd: valueUsd,
        isIncluded: scheduleDue,
        nextDueDate: settings.nextRamadanDueDate,
        exclusionReason: scheduleDue ? null : 'Not due until Ramadan date',
      );
    }

    if (asset.boughtDate == null) {
      return ZakatAssetAssessment(
        asset: asset,
        valueUsd: valueUsd,
        isIncluded: false,
        exclusionReason: 'Holding start date required',
      );
    }

    final cycleStart = payments[asset.id]?.paidAt ?? asset.boughtDate!;
    final nextDueDate = cycleStart.add(const Duration(days: _hawlDays));
    final due = !today.isBefore(nextDueDate);
    return ZakatAssetAssessment(
      asset: asset,
      valueUsd: valueUsd,
      isIncluded: due,
      nextDueDate: nextDueDate,
      exclusionReason: due ? null : 'Not held for one lunar year yet',
    );
  }

  static bool _isScheduleDue(ZakatSettings settings, DateTime today) {
    if (settings.scheduleMode == ZakatScheduleMode.individualDueDates) {
      return true;
    }
    final dueDate = settings.nextRamadanDueDate;
    return dueDate != null && !today.isBefore(dueDate);
  }

  static double? _assetValueUsd(Asset asset, MetalPriceSnapshot prices) {
    if (!asset.type.isMetal) {
      final rate = prices.usdRateFor(asset.currency);
      return rate == null ? null : asset.amount * rate;
    }
    final pricePerGram = asset.type == AssetType.gold
        ? prices.goldPerGramUsd
        : prices.silverPerGramUsd;
    final purityFactor = (asset.purity ?? 100) / 100;
    return asset.amount * purityFactor * pricePerGram;
  }

  static String? _messageFor({
    required ZakatSettings settings,
    required bool scheduleDue,
    required double eligibleWealthUsd,
    required double nisabThresholdUsd,
  }) {
    if (settings.scheduleMode == ZakatScheduleMode.ramadanAnnual &&
        settings.nextRamadanDueDate == null) {
      return 'Choose your next Ramadan payment date to activate this mode.';
    }
    if (!scheduleDue) {
      return 'Your Ramadan zakat date has not arrived yet.';
    }
    if (eligibleWealthUsd < nisabThresholdUsd) {
      return 'Currently due holdings are below the selected nisab threshold.';
    }
    return null;
  }
}
