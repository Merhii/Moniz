// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'money_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MoneyCategoryAdapter extends TypeAdapter<MoneyCategory> {
  @override
  final int typeId = 10;

  @override
  MoneyCategory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MoneyCategory(
      id: fields[0] as String,
      label: fields[1] as String,
      direction: fields[2] as MoneyDirection,
      isBuiltIn: fields[3] == null ? false : fields[3] as bool,
      isHidden: fields[4] == null ? false : fields[4] as bool,
      sortIndex: fields[5] == null ? 0 : fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, MoneyCategory obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.direction)
      ..writeByte(3)
      ..write(obj.isBuiltIn)
      ..writeByte(4)
      ..write(obj.isHidden)
      ..writeByte(5)
      ..write(obj.sortIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoneyCategoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MoneyAccountAdapter extends TypeAdapter<MoneyAccount> {
  @override
  final int typeId = 11;

  @override
  MoneyAccount read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MoneyAccount(
      id: fields[0] as String,
      label: fields[1] as String,
      currency: fields[2] == null ? 'USD' : fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, MoneyAccount obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.currency);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoneyAccountAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MoneyEntryAdapter extends TypeAdapter<MoneyEntry> {
  @override
  final int typeId = 12;

  @override
  MoneyEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MoneyEntry(
      id: fields[0] as String,
      amount: fields[1] as double,
      direction: fields[2] as MoneyDirection,
      happenedAt: fields[4] as DateTime,
      currency: fields[3] == null ? 'USD' : fields[3] as String,
      accountId: fields[5] == null ? 'default' : fields[5] as String,
      categoryId: fields[6] as String?,
      note: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MoneyEntry obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.direction)
      ..writeByte(3)
      ..write(obj.currency)
      ..writeByte(4)
      ..write(obj.happenedAt)
      ..writeByte(5)
      ..write(obj.accountId)
      ..writeByte(6)
      ..write(obj.categoryId)
      ..writeByte(7)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoneyEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MoneyDirectionAdapter extends TypeAdapter<MoneyDirection> {
  @override
  final int typeId = 9;

  @override
  MoneyDirection read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MoneyDirection.income;
      case 1:
        return MoneyDirection.expense;
      default:
        return MoneyDirection.income;
    }
  }

  @override
  void write(BinaryWriter writer, MoneyDirection obj) {
    switch (obj) {
      case MoneyDirection.income:
        writer.writeByte(0);
        break;
      case MoneyDirection.expense:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoneyDirectionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
