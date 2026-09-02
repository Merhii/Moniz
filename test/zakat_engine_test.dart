import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/services/zakat_engine.dart';

void main() {
  test(
    'ramadan mode assesses all active holdings only once due date arrives',
    () {
      final dueResult = ZakatEngine.calculate(
        assets: [
          const Asset(
            id: 'cash',
            type: AssetType.cash,
            amount: 1000,
            unit: 'USD',
          ),
          Asset(
            id: 'sold',
            type: AssetType.gold,
            amount: 20,
            unit: 'g',
            purity: 100,
            soldDate: DateTime(2026, 1, 1),
          ),
        ],
        prices: _prices(),
        settings: ZakatSettings(nextRamadanDueDate: DateTime(2026, 3, 1)),
        payments: const {},
        today: DateTime(2026, 3, 1),
      );

      expect(dueResult.isScheduleDue, isTrue);
      expect(dueResult.eligibleWealthUsd, 1000);
      expect(dueResult.amountDueUsd, 25);
      expect(dueResult.assessments.last.exclusionReason, 'Sold asset');

      final beforeDateResult = ZakatEngine.calculate(
        assets: const [
          Asset(id: 'cash', type: AssetType.cash, amount: 1000, unit: 'USD'),
        ],
        prices: _prices(),
        settings: ZakatSettings(nextRamadanDueDate: DateTime(2026, 3, 1)),
        payments: const {},
        today: DateTime(2026, 2, 28),
      );

      expect(beforeDateResult.amountDueUsd, 0);
      expect(beforeDateResult.assessments.single.isIncluded, isFalse);
    },
  );

  test(
    'monthly mode includes only holdings past a lunar year and not repaid',
    () {
      final result = ZakatEngine.calculate(
        assets: [
          Asset(
            id: 'mature-cash',
            type: AssetType.cash,
            amount: 1000,
            unit: 'USD',
            boughtDate: DateTime(2025, 1, 1),
          ),
          Asset(
            id: 'new-gold',
            type: AssetType.gold,
            amount: 10,
            unit: 'g',
            purity: 100,
            boughtDate: DateTime(2025, 12, 1),
          ),
          const Asset(
            id: 'missing-date',
            type: AssetType.bankSavings,
            amount: 800,
            unit: 'USD',
          ),
        ],
        prices: _prices(),
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: {
          'new-gold': ZakatPaymentRecord(
            referenceId: 'new-gold',
            paidAt: DateTime(2025, 12, 1),
            amountUsd: 0,
          ),
        },
        today: DateTime(2026, 1, 1),
      );

      expect(result.includedAssessments.map((item) => item.asset.id), [
        'mature-cash',
      ]);
      expect(result.amountDueUsd, 25);
      expect(
        result.assessments.last.exclusionReason,
        'Holding start date required',
      );
    },
  );

  test('supports gold or silver nisab thresholds from live prices', () {
    final goldResult = ZakatEngine.calculate(
      assets: const [],
      prices: _prices(),
      settings: const ZakatSettings(nisabStandard: NisabStandard.gold),
      payments: const {},
      today: DateTime(2026, 1, 1),
    );
    final silverResult = ZakatEngine.calculate(
      assets: const [],
      prices: _prices(),
      settings: const ZakatSettings(nisabStandard: NisabStandard.silver),
      payments: const {},
      today: DateTime(2026, 1, 1),
    );

    expect(goldResult.nisabThresholdUsd, 8500);
    expect(silverResult.nisabThresholdUsd, 612.36);
  });

  group('what is blocking a calculation', () {
    test('names prices and the Ramadan date together, not one then the '
        'other', () {
      final result = ZakatEngine.calculate(
        assets: const [
          Asset(id: 'cash', type: AssetType.cash, amount: 50000, unit: 'USD'),
        ],
        prices: null,
        settings: const ZakatSettings(),
        payments: const {},
        today: DateTime(2026, 9, 2),
      );

      // A fresh install has neither. Reporting only the prices sent people
      // to Settings, then straight into a second dead end.
      expect(result.canCalculate, isFalse);
      expect(result.message, contains('prices'));
      expect(result.message, contains('Ramadan date'));
    });

    test('mentions only prices when the schedule is already set up', () {
      final result = ZakatEngine.calculate(
        assets: const [
          Asset(id: 'cash', type: AssetType.cash, amount: 50000, unit: 'USD'),
        ],
        prices: null,
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: const {},
        today: DateTime(2026, 9, 2),
      );

      expect(result.message, contains('prices'));
      expect(result.message, isNot(contains('Ramadan')));
    });

    test('mentions only prices when a Ramadan date is already chosen', () {
      final result = ZakatEngine.calculate(
        assets: const [
          Asset(id: 'cash', type: AssetType.cash, amount: 50000, unit: 'USD'),
        ],
        prices: null,
        settings: ZakatSettings(nextRamadanDueDate: DateTime(2027, 3, 1)),
        payments: const {},
        today: DateTime(2026, 9, 2),
      );

      expect(result.message, contains('prices'));
      expect(result.message, isNot(contains('Ramadan')));
    });

    test('once prices arrive, the Ramadan date is still asked for', () {
      final result = ZakatEngine.calculate(
        assets: const [
          Asset(id: 'cash', type: AssetType.cash, amount: 50000, unit: 'USD'),
        ],
        prices: _prices(),
        settings: const ZakatSettings(),
        payments: const {},
        today: DateTime(2026, 9, 2),
      );

      expect(result.canCalculate, isTrue);
      expect(result.message, contains('Ramadan'));
    });
  });

  group('payments across schedule modes', () {
    final asset = Asset(
      id: 'cash',
      type: AssetType.cash,
      amount: 50000,
      unit: 'USD',
      boughtDate: DateTime(2025, 1, 1),
    );

    ZakatResult assess(
      DateTime today,
      Map<String, ZakatPaymentRecord> payments,
    ) {
      return ZakatEngine.calculate(
        assets: [asset],
        prices: _prices(),
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: payments,
        today: today,
      );
    }

    test('an annual Ramadan payment settles per-holding cycles too', () {
      final paidAt = DateTime(2025, 12, 21);
      final result = assess(paidAt.add(const Duration(days: 1)), {
        ZakatEngine.annualPaymentKey: ZakatPaymentRecord(
          referenceId: ZakatEngine.annualPaymentKey,
          paidAt: paidAt,
          amountUsd: 1250,
        ),
      });

      // Previously this billed the full amount again the day after paying,
      // because per-holding assessment only looked for a per-holding record.
      expect(result.hasPaymentDue, isFalse);
      expect(result.amountDueUsd, 0);
      expect(
        result.assessments.single.nextDueDate,
        paidAt.add(const Duration(days: 354)),
      );
    });

    test('a payment older than the holding does not settle it', () {
      // Bought 2025-01-01; an annual payment from before that cannot have
      // covered wealth not yet held.
      final result = assess(DateTime(2026, 1, 1), {
        ZakatEngine.annualPaymentKey: ZakatPaymentRecord(
          referenceId: ZakatEngine.annualPaymentKey,
          paidAt: DateTime(2024, 6, 1),
          amountUsd: 1250,
        ),
      });

      expect(result.hasPaymentDue, isTrue);
      expect(
        result.assessments.single.nextDueDate,
        DateTime(2025, 1, 1).add(const Duration(days: 354)),
      );
    });

    test('the later of a holding and annual payment wins', () {
      final result = assess(DateTime(2027, 1, 1), {
        'cash': ZakatPaymentRecord(
          referenceId: 'cash',
          paidAt: DateTime(2025, 12, 21),
          amountUsd: 1250,
        ),
        ZakatEngine.annualPaymentKey: ZakatPaymentRecord(
          referenceId: ZakatEngine.annualPaymentKey,
          paidAt: DateTime(2026, 3, 1),
          amountUsd: 1250,
        ),
      });

      expect(
        result.assessments.single.nextDueDate,
        DateTime(2026, 3, 1).add(const Duration(days: 354)),
      );
    });
  });

  group('message when nothing is eligible', () {
    test('names the lunar year, not the nisab, and dates the first due', () {
      final result = ZakatEngine.calculate(
        assets: [
          Asset(
            id: 'young-gold',
            type: AssetType.gold,
            amount: 200,
            unit: 'g',
            purity: 100,
            boughtDate: DateTime(2026, 1, 10),
          ),
          Asset(
            id: 'younger-cash',
            type: AssetType.cash,
            amount: 50000,
            unit: 'USD',
            boughtDate: DateTime(2026, 2, 1),
          ),
        ],
        prices: _prices(),
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: const {},
        today: DateTime(2026, 3, 1),
      );

      // Well above the 8500 nisab, so "below the threshold" would be a lie.
      expect(result.eligibleWealthUsd, 0);
      expect(result.amountDueUsd, 0);
      expect(result.message, isNot(contains('nisab')));
      expect(result.message, contains('lunar year'));
      // 2026-01-10 + 354 days.
      expect(result.message, contains('2026-12-30'));
    });

    test('counts holdings that are missing a start date', () {
      final result = ZakatEngine.calculate(
        assets: const [
          Asset(id: 'a', type: AssetType.cash, amount: 9000, unit: 'USD'),
          Asset(id: 'b', type: AssetType.cash, amount: 9000, unit: 'USD'),
        ],
        prices: _prices(),
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: const {},
        today: DateTime(2026, 3, 1),
      );

      expect(
        result.message,
        '2 holdings need a start date before they can be '
        'assessed.',
      );
    });

    test('asks for a holding when the ledger is empty', () {
      final result = ZakatEngine.calculate(
        assets: const [],
        prices: _prices(),
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: const {},
        today: DateTime(2026, 3, 1),
      );

      expect(result.message, 'Add a holding to calculate your zakat.');
    });

    test('still blames the nisab when something is genuinely assessed', () {
      final result = ZakatEngine.calculate(
        assets: [
          Asset(
            id: 'mature-but-small',
            type: AssetType.cash,
            amount: 100,
            unit: 'USD',
            boughtDate: DateTime(2024, 1, 1),
          ),
        ],
        prices: _prices(),
        settings: const ZakatSettings(
          scheduleMode: ZakatScheduleMode.individualDueDates,
        ),
        payments: const {},
        today: DateTime(2026, 3, 1),
      );

      expect(result.eligibleWealthUsd, 100);
      expect(
        result.message,
        'Currently due holdings are below the selected nisab threshold.',
      );
    });
  });
}

MetalPriceSnapshot _prices() {
  return MetalPriceSnapshot(
    goldPerGramUsd: 100,
    silverPerGramUsd: 1,
    priceTimestamp: DateTime.utc(2026, 1, 1),
    fetchedAt: DateTime.utc(2026, 1, 1),
  );
}
