// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'portfolio_snapshot.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PortfolioSnapshotAdapter extends TypeAdapter<PortfolioSnapshot> {
  @override
  final int typeId = 7;

  @override
  PortfolioSnapshot read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PortfolioSnapshot(
      id: fields[0] as String,
      capturedAt: fields[1] as DateTime,
      totalUsd: fields[2] as double,
      cashUsd: fields[3] as double,
      bankSavingsUsd: fields[4] as double,
      goldUsd: fields[5] as double,
      silverUsd: fields[6] as double,
    );
  }

  @override
  void write(BinaryWriter writer, PortfolioSnapshot obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.capturedAt)
      ..writeByte(2)
      ..write(obj.totalUsd)
      ..writeByte(3)
      ..write(obj.cashUsd)
      ..writeByte(4)
      ..write(obj.bankSavingsUsd)
      ..writeByte(5)
      ..write(obj.goldUsd)
      ..writeByte(6)
      ..write(obj.silverUsd);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PortfolioSnapshotAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
