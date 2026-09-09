import '../models/asset.dart';
import '../models/metal_price_snapshot.dart';
import '../models/money_entry.dart';
import '../models/zakat_settings.dart';
import 'cash_account_migration.dart';
import 'currency_converter.dart';
import 'money_ledger.dart';

class ZakatAssetAssessment {
  const ZakatAssetAssessment({
    required this.asset,
    required this.valueUsd,
    required this.isIncluded,
    this.nextDueDate,
    this.exclusionReason,
    this.valuationNote,
  });

  final Asset asset;
  final double? valueUsd;
  final bool isIncluded;
  final DateTime? nextDueDate;
  final String? exclusionReason;

  /// Why the value differs from the amount on the holding, when it does.
  ///
  /// A spending wallet is assessed on what stayed in it, not on the figure
  /// typed into the holding, and a number that quietly disagrees with the
  /// Holdings screen reads as a bug unless it says why.
  final String? valuationNote;
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

  /// Key the annual Ramadan payment is recorded under. It is not tied to any
  /// one holding, so per-holding assessment has to look for it explicitly.
  static const annualPaymentKey = 'annual_ramadan';

  static const soldExclusion = 'Sold asset';
  static const unsupportedCurrencyExclusion = 'Unsupported currency';
  static const ramadanNotDueExclusion = 'Not due until Ramadan date';
  static const missingStartDateExclusion = 'Holding start date required';
  static const hawlNotReachedExclusion = 'Not held for one lunar year yet';

  static const lowestBalanceNote = 'Lowest balance over the year';
  static const ramadanWalletNote = 'Wallet balance on the Ramadan date';

  static ZakatResult calculate({
    required List<Asset> assets,
    required MetalPriceSnapshot? prices,
    required ZakatSettings settings,
    required Map<String, ZakatPaymentRecord> payments,
    required DateTime today,
    List<MoneyEntry> moneyEntries = const [],
    List<MoneyAccount> accounts = const [],
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
        message: _blockedMessage(settings),
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
            moneyEntries: moneyEntries,
            accounts: accounts,
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
        assessments: assessments,
        eligibleWealthUsd: eligibleWealthUsd,
        nisabThresholdUsd: nisabThresholdUsd,
      ),
    );
  }

  /// Everything standing between the user and a zakat figure, at once.
  ///
  /// Missing prices short-circuit the whole calculation, so a new user was
  /// told to refresh prices and only afterwards discovered they also had to
  /// pick a Ramadan date - two dead ends in a row instead of one list.
  static String _blockedMessage(ZakatSettings settings) {
    final needsRamadanDate =
        settings.scheduleMode == ZakatScheduleMode.ramadanAnnual &&
        settings.nextRamadanDueDate == null;
    if (!needsRamadanDate) {
      return 'Refresh metal prices in Settings to calculate the current nisab '
          'and zakat.';
    }
    return 'Zakat needs two things here: refresh metal prices in Settings, '
        'and choose your next Ramadan date.';
  }

  static ZakatAssetAssessment _assessAsset({
    required Asset asset,
    required MetalPriceSnapshot prices,
    required ZakatSettings settings,
    required Map<String, ZakatPaymentRecord> payments,
    required DateTime today,
    required bool scheduleDue,
    required List<MoneyEntry> moneyEntries,
    required List<MoneyAccount> accounts,
  }) {
    if (asset.isSold) {
      return ZakatAssetAssessment(
        asset: asset,
        valueUsd: null,
        isIncluded: false,
        exclusionReason: soldExclusion,
      );
    }

    final valueUsd = _assetValueUsd(asset, prices);
    if (valueUsd == null) {
      return ZakatAssetAssessment(
        asset: asset,
        valueUsd: null,
        isIncluded: false,
        exclusionReason: unsupportedCurrencyExclusion,
      );
    }

    final wallet = _walletFor(asset, accounts);

    if (settings.scheduleMode == ZakatScheduleMode.ramadanAnnual) {
      // On the Ramadan date everything held is counted in full: the schedule
      // fixes one day for the whole portfolio, so there is no per-holding
      // year to take a low-water mark across. The obligation crystallises on
      // that date, so that is the day the balance is read on.
      final asOf = settings.nextRamadanDueDate ?? today;
      return ZakatAssetAssessment(
        asset: asset,
        valueUsd: wallet == null
            ? valueUsd
            : _walletValueUsd(
                wallet: wallet,
                moneyEntries: moneyEntries,
                prices: prices,
                asOf: asOf,
              ),
        isIncluded: scheduleDue,
        nextDueDate: settings.nextRamadanDueDate,
        exclusionReason: scheduleDue ? null : ramadanNotDueExclusion,
        valuationNote: wallet == null ? null : ramadanWalletNote,
      );
    }

    if (asset.boughtDate == null) {
      return ZakatAssetAssessment(
        asset: asset,
        valueUsd: valueUsd,
        isIncluded: false,
        exclusionReason: missingStartDateExclusion,
      );
    }

    final nextDueDate = _nextDueDate(
      boughtDate: asset.boughtDate!,
      settledAt: _settledAt(asset, payments),
    );
    final due = !today.isBefore(nextDueDate);

    // Only what stayed in the wallet all year completed the hawl. Money that
    // came in and went back out was not held for the year, so charging zakat
    // on the closing figure would charge it on wealth that was already spent.
    final lowest = wallet == null
        ? null
        : _lowestWalletValueUsd(
            wallet: wallet,
            moneyEntries: moneyEntries,
            prices: prices,
            to: nextDueDate,
          );

    return ZakatAssetAssessment(
      asset: asset,
      valueUsd: lowest ?? valueUsd,
      isIncluded: due,
      nextDueDate: nextDueDate,
      exclusionReason: due ? null : 'Not held for one lunar year yet',
      valuationNote: lowest == null ? null : lowestBalanceNote,
    );
  }

  /// The wallet a cash holding was migrated into, if it has one.
  static MoneyAccount? _walletFor(Asset asset, List<MoneyAccount> accounts) {
    if (asset.type != AssetType.cash) return null;
    final id = CashAccountMigrationPlanner.accountIdFor(asset.id);
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  static double _walletValueUsd({
    required MoneyAccount wallet,
    required List<MoneyEntry> moneyEntries,
    required MetalPriceSnapshot prices,
    required DateTime asOf,
  }) {
    final balance = MoneyLedger.balanceOf(
      moneyEntries,
      accountId: wallet.id,
      currency: CurrencyConverter.defaultCurrency,
      asOf: asOf,
      account: wallet,
      prices: prices,
    );
    // An overdrawn wallet is a debt, not wealth to be tithed.
    return balance < 0 ? 0 : balance;
  }

  static double _lowestWalletValueUsd({
    required MoneyAccount wallet,
    required List<MoneyEntry> moneyEntries,
    required MetalPriceSnapshot prices,
    required DateTime to,
  }) {
    final lowest = MoneyLedger.minimumBalanceOf(
      moneyEntries,
      accountId: wallet.id,
      currency: CurrencyConverter.defaultCurrency,
      from: to.subtract(const Duration(days: _hawlDays)),
      to: to,
      account: wallet,
      prices: prices,
    );
    return lowest < 0 ? 0 : lowest;
  }

  /// The next anniversary that has not been settled.
  ///
  /// Anniversaries sit on a fixed grid from the holding's own start date, one
  /// lunar year apart. Previously the next one was measured from the day
  /// zakat was handed over, so paying 60 days late pushed it 60 days out and
  /// every late payment moved it again - a habitually late payer would drift
  /// a whole year off over time, skipping an obligation.
  ///
  /// A payment settles the anniversary year it falls in, and the next one
  /// stays where it always was. Paying early still settles the coming year,
  /// so nobody is charged twice for it.
  static DateTime _nextDueDate({
    required DateTime boughtDate,
    DateTime? settledAt,
  }) {
    const cycle = Duration(days: _hawlDays);
    if (settledAt == null) return boughtDate.add(cycle);
    final elapsedDays = settledAt.difference(boughtDate).inDays;
    final settledYears = elapsedDays < _hawlDays ? 1 : elapsedDays ~/ _hawlDays;
    return boughtDate.add(Duration(days: _hawlDays * (settledYears + 1)));
  }

  /// When zakat was last settled on [asset], from either schedule.
  ///
  /// A payment made under the Ramadan schedule is recorded once, against
  /// [annualPaymentKey], not against each holding. Ignoring it here meant that
  /// switching to per-holding dates looked no different from never having paid
  /// at all, and asked for the same wealth a second time.
  ///
  /// Payments predating the holding are skipped: they cannot have settled
  /// wealth that was not held yet.
  static DateTime? _settledAt(
    Asset asset,
    Map<String, ZakatPaymentRecord> payments,
  ) {
    final boughtDate = asset.boughtDate;
    final candidates =
        [
          payments[asset.id]?.paidAt,
          payments[annualPaymentKey]?.paidAt,
        ].whereType<DateTime>().where(
          (paidAt) => boughtDate == null || !paidAt.isBefore(boughtDate),
        );
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a.isAfter(b) ? a : b);
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
      final rate = CurrencyConverter.usdRateFor(asset.currency, prices: prices);
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
    required List<ZakatAssetAssessment> assessments,
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
    // Nothing was assessed at all, so the nisab comparison below would be
    // vacuously true and would blame a threshold the holdings never reached.
    if (!assessments.any((assessment) => assessment.isIncluded)) {
      return _nothingEligibleMessage(assessments);
    }
    if (eligibleWealthUsd < nisabThresholdUsd) {
      return 'Currently due holdings are below the selected nisab threshold.';
    }
    return null;
  }

  static String _nothingEligibleMessage(
    List<ZakatAssetAssessment> assessments,
  ) {
    final unsold = assessments
        .where((assessment) => !assessment.asset.isSold)
        .toList();
    if (unsold.isEmpty) {
      return 'Add a holding to calculate your zakat.';
    }

    final needStartDate = unsold
        .where(
          (assessment) =>
              assessment.exclusionReason == missingStartDateExclusion,
        )
        .length;
    final waitingOnHawl = unsold
        .where(
          (assessment) => assessment.exclusionReason == hawlNotReachedExclusion,
        )
        .toList();

    final sentences = <String>[];
    if (waitingOnHawl.isNotEmpty) {
      final earliest = waitingOnHawl
          .map((assessment) => assessment.nextDueDate)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (earliest, date) =>
                earliest == null || date.isBefore(earliest) ? date : earliest,
          );
      sentences.add(
        earliest == null
            ? 'None of your holdings have been held for a lunar year yet.'
            : 'None of your holdings have been held for a lunar year yet; '
                  'the first becomes eligible on ${_formatDate(earliest)}.',
      );
    }
    if (needStartDate > 0) {
      sentences.add(
        needStartDate == 1
            ? '1 holding needs a start date before it can be assessed.'
            : '$needStartDate holdings need a start date before they can be '
                  'assessed.',
      );
    }
    if (sentences.isEmpty) {
      return 'None of your holdings are eligible for zakat right now.';
    }
    return sentences.join(' ');
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
