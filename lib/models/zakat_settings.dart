import 'package:hive/hive.dart';

part 'zakat_settings.g.dart';

@HiveType(typeId: 3)
enum ZakatScheduleMode {
  @HiveField(0)
  ramadanAnnual,
  @HiveField(1)
  individualDueDates,
}

extension ZakatScheduleModeDetails on ZakatScheduleMode {
  String get label {
    switch (this) {
      case ZakatScheduleMode.ramadanAnnual:
        return 'Pay each Ramadan';
      case ZakatScheduleMode.individualDueDates:
        return 'Check holdings monthly';
    }
  }
}

@HiveType(typeId: 4)
enum NisabStandard {
  @HiveField(0)
  gold,
  @HiveField(1)
  silver,
}

extension NisabStandardDetails on NisabStandard {
  String get label {
    switch (this) {
      case NisabStandard.gold:
        return 'Gold nisab';
      case NisabStandard.silver:
        return 'Silver nisab';
    }
  }
}

@HiveType(typeId: 5)
class ZakatSettings {
  const ZakatSettings({
    this.scheduleMode = ZakatScheduleMode.ramadanAnnual,
    this.nisabStandard = NisabStandard.silver,
    this.nextRamadanDueDate,
  });

  @HiveField(0, defaultValue: ZakatScheduleMode.ramadanAnnual)
  final ZakatScheduleMode scheduleMode;

  @HiveField(1, defaultValue: NisabStandard.silver)
  final NisabStandard nisabStandard;

  @HiveField(2)
  final DateTime? nextRamadanDueDate;

  ZakatSettings copyWith({
    ZakatScheduleMode? scheduleMode,
    NisabStandard? nisabStandard,
    DateTime? nextRamadanDueDate,
    bool clearRamadanDueDate = false,
  }) {
    return ZakatSettings(
      scheduleMode: scheduleMode ?? this.scheduleMode,
      nisabStandard: nisabStandard ?? this.nisabStandard,
      nextRamadanDueDate: clearRamadanDueDate
          ? null
          : nextRamadanDueDate ?? this.nextRamadanDueDate,
    );
  }
}

@HiveType(typeId: 6)
class ZakatPaymentRecord {
  const ZakatPaymentRecord({
    required this.referenceId,
    required this.paidAt,
    required this.amountUsd,
  });

  @HiveField(0)
  final String referenceId;

  @HiveField(1)
  final DateTime paidAt;

  @HiveField(2)
  final double amountUsd;
}
