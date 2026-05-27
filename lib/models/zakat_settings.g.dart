// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'zakat_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ZakatSettingsAdapter extends TypeAdapter<ZakatSettings> {
  @override
  final int typeId = 5;

  @override
  ZakatSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ZakatSettings(
      scheduleMode: fields[0] == null
          ? ZakatScheduleMode.ramadanAnnual
          : fields[0] as ZakatScheduleMode,
      nisabStandard: fields[1] == null
          ? NisabStandard.silver
          : fields[1] as NisabStandard,
      nextRamadanDueDate: fields[2] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ZakatSettings obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.scheduleMode)
      ..writeByte(1)
      ..write(obj.nisabStandard)
      ..writeByte(2)
      ..write(obj.nextRamadanDueDate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZakatSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ZakatPaymentRecordAdapter extends TypeAdapter<ZakatPaymentRecord> {
  @override
  final int typeId = 6;

  @override
  ZakatPaymentRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ZakatPaymentRecord(
      referenceId: fields[0] as String,
      paidAt: fields[1] as DateTime,
      amountUsd: fields[2] as double,
    );
  }

  @override
  void write(BinaryWriter writer, ZakatPaymentRecord obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.referenceId)
      ..writeByte(1)
      ..write(obj.paidAt)
      ..writeByte(2)
      ..write(obj.amountUsd);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZakatPaymentRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ZakatScheduleModeAdapter extends TypeAdapter<ZakatScheduleMode> {
  @override
  final int typeId = 3;

  @override
  ZakatScheduleMode read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ZakatScheduleMode.ramadanAnnual;
      case 1:
        return ZakatScheduleMode.individualDueDates;
      default:
        return ZakatScheduleMode.ramadanAnnual;
    }
  }

  @override
  void write(BinaryWriter writer, ZakatScheduleMode obj) {
    switch (obj) {
      case ZakatScheduleMode.ramadanAnnual:
        writer.writeByte(0);
        break;
      case ZakatScheduleMode.individualDueDates:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZakatScheduleModeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class NisabStandardAdapter extends TypeAdapter<NisabStandard> {
  @override
  final int typeId = 4;

  @override
  NisabStandard read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return NisabStandard.gold;
      case 1:
        return NisabStandard.silver;
      default:
        return NisabStandard.gold;
    }
  }

  @override
  void write(BinaryWriter writer, NisabStandard obj) {
    switch (obj) {
      case NisabStandard.gold:
        writer.writeByte(0);
        break;
      case NisabStandard.silver:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NisabStandardAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
