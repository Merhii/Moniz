// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recurring_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RecurringEntryAdapter extends TypeAdapter<RecurringEntry> {
  @override
  final int typeId = 14;

  @override
  RecurringEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RecurringEntry(
      id: fields[0] as String,
      amount: fields[1] as double,
      direction: fields[2] as MoneyDirection,
      frequency: fields[7] as RecurrenceFrequency,
      dayOfPeriod: fields[8] as int,
      startsOn: fields[9] as DateTime,
      currency: fields[3] == null ? 'USD' : fields[3] as String,
      categoryId: fields[4] as String?,
      accountId: fields[5] == null ? 'default' : fields[5] as String,
      note: fields[6] as String?,
      lastRunOn: fields[10] as DateTime?,
      isPaused: fields[11] == null ? false : fields[11] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, RecurringEntry obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.direction)
      ..writeByte(3)
      ..write(obj.currency)
      ..writeByte(4)
      ..write(obj.categoryId)
      ..writeByte(5)
      ..write(obj.accountId)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.frequency)
      ..writeByte(8)
      ..write(obj.dayOfPeriod)
      ..writeByte(9)
      ..write(obj.startsOn)
      ..writeByte(10)
      ..write(obj.lastRunOn)
      ..writeByte(11)
      ..write(obj.isPaused);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecurringEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RecurrenceFrequencyAdapter extends TypeAdapter<RecurrenceFrequency> {
  @override
  final int typeId = 13;

  @override
  RecurrenceFrequency read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return RecurrenceFrequency.weekly;
      case 1:
        return RecurrenceFrequency.monthly;
      default:
        return RecurrenceFrequency.weekly;
    }
  }

  @override
  void write(BinaryWriter writer, RecurrenceFrequency obj) {
    switch (obj) {
      case RecurrenceFrequency.weekly:
        writer.writeByte(0);
        break;
      case RecurrenceFrequency.monthly:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecurrenceFrequencyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
