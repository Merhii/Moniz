// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssetAdapter extends TypeAdapter<Asset> {
  @override
  final int typeId = 1;

  @override
  Asset read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Asset(
      id: fields[0] as String,
      type: fields[1] as AssetType,
      amount: fields[2] as double,
      unit: fields[3] as String,
      purity: fields[4] as double?,
      boughtDate: fields[5] as DateTime?,
      boughtPrice: fields[6] as double?,
      soldDate: fields[7] as DateTime?,
      soldPrice: fields[8] as double?,
      note: fields[9] as String?,
      currency: fields[10] == null ? 'USD' : fields[10] as String,
      tag: fields[11] as AssetTag?,
    );
  }

  @override
  void write(BinaryWriter writer, Asset obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.unit)
      ..writeByte(4)
      ..write(obj.purity)
      ..writeByte(5)
      ..write(obj.boughtDate)
      ..writeByte(6)
      ..write(obj.boughtPrice)
      ..writeByte(7)
      ..write(obj.soldDate)
      ..writeByte(8)
      ..write(obj.soldPrice)
      ..writeByte(9)
      ..write(obj.note)
      ..writeByte(10)
      ..write(obj.currency)
      ..writeByte(11)
      ..write(obj.tag);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AssetTypeAdapter extends TypeAdapter<AssetType> {
  @override
  final int typeId = 0;

  @override
  AssetType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AssetType.cash;
      case 1:
        return AssetType.bankSavings;
      case 2:
        return AssetType.gold;
      case 3:
        return AssetType.silver;
      default:
        return AssetType.cash;
    }
  }

  @override
  void write(BinaryWriter writer, AssetType obj) {
    switch (obj) {
      case AssetType.cash:
        writer.writeByte(0);
        break;
      case AssetType.bankSavings:
        writer.writeByte(1);
        break;
      case AssetType.gold:
        writer.writeByte(2);
        break;
      case AssetType.silver:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AssetTagAdapter extends TypeAdapter<AssetTag> {
  @override
  final int typeId = 8;

  @override
  AssetTag read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AssetTag.freelance;
      case 1:
        return AssetTag.emergency;
      case 2:
        return AssetTag.gift;
      case 3:
        return AssetTag.salary;
      case 4:
        return AssetTag.businessProfit;
      default:
        return AssetTag.freelance;
    }
  }

  @override
  void write(BinaryWriter writer, AssetTag obj) {
    switch (obj) {
      case AssetTag.freelance:
        writer.writeByte(0);
        break;
      case AssetTag.emergency:
        writer.writeByte(1);
        break;
      case AssetTag.gift:
        writer.writeByte(2);
        break;
      case AssetTag.salary:
        writer.writeByte(3);
        break;
      case AssetTag.businessProfit:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetTagAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
