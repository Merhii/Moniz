import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/zakat_settings.dart';
import '../services/zakat_engine.dart';

class ZakatNotifier extends StateNotifier<ZakatSettings> {
  ZakatNotifier({
    required Box<ZakatSettings> settingsBox,
    required Box<ZakatPaymentRecord> paymentBox,
  }) : _settingsBox = settingsBox,
       _paymentBox = paymentBox,
       super(settingsBox.get(_settingsKey) ?? const ZakatSettings());

  static const _settingsKey = 'settings';
  static const _annualPaymentKey = 'annual_ramadan';
  static const _hawlDays = 354;

  final Box<ZakatSettings> _settingsBox;
  final Box<ZakatPaymentRecord> _paymentBox;

  Map<String, ZakatPaymentRecord> get payments => Map.fromEntries(
    _paymentBox.values.map((record) => MapEntry(record.referenceId, record)),
  );

  Future<void> setScheduleMode(ZakatScheduleMode mode) async {
    state = state.copyWith(scheduleMode: mode);
    await _settingsBox.put(_settingsKey, state);
  }

  Future<void> setNisabStandard(NisabStandard standard) async {
    state = state.copyWith(nisabStandard: standard);
    await _settingsBox.put(_settingsKey, state);
  }

  Future<void> setRamadanDueDate(DateTime date) async {
    state = state.copyWith(nextRamadanDueDate: date);
    await _settingsBox.put(_settingsKey, state);
  }

  Future<void> recordPayment(ZakatResult result, DateTime paidAt) async {
    if (!result.hasPaymentDue) return;

    if (state.scheduleMode == ZakatScheduleMode.ramadanAnnual) {
      await _paymentBox.put(
        _annualPaymentKey,
        ZakatPaymentRecord(
          referenceId: _annualPaymentKey,
          paidAt: paidAt,
          amountUsd: result.amountDueUsd,
        ),
      );
      var nextDueDate = state.nextRamadanDueDate ?? paidAt;
      while (!nextDueDate.isAfter(paidAt)) {
        nextDueDate = nextDueDate.add(const Duration(days: _hawlDays));
      }
      await setRamadanDueDate(nextDueDate);
      return;
    }

    for (final assessment in result.includedAssessments) {
      await _paymentBox.put(
        assessment.asset.id,
        ZakatPaymentRecord(
          referenceId: assessment.asset.id,
          paidAt: paidAt,
          amountUsd: (assessment.valueUsd ?? 0) * 0.025,
        ),
      );
    }
    state = state.copyWith();
  }
}

final zakatProvider = StateNotifierProvider<ZakatNotifier, ZakatSettings>(
  (ref) => ZakatNotifier(
    settingsBox: Hive.box<ZakatSettings>('zakatSettings'),
    paymentBox: Hive.box<ZakatPaymentRecord>('zakatPayments'),
  ),
);
