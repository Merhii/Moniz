// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metal_price_snapshot.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MetalPriceSnapshotAdapter extends TypeAdapter<MetalPriceSnapshot> {
  @override
  final int typeId = 2;

  @override
  MetalPriceSnapshot read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MetalPriceSnapshot(
      goldPerGramUsd: fields[0] as double,
      silverPerGramUsd: fields[1] as double,
      priceTimestamp: fields[2] as DateTime,
      fetchedAt: fields[3] as DateTime,
      eurToUsd: fields[4] as double?,
      aedToUsd: fields[5] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, MetalPriceSnapshot obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.goldPerGramUsd)
      ..writeByte(1)
      ..write(obj.silverPerGramUsd)
      ..writeByte(2)
      ..write(obj.priceTimestamp)
      ..writeByte(3)
      ..write(obj.fetchedAt)
      ..writeByte(4)
      ..write(obj.eurToUsd)
      ..writeByte(5)
      ..write(obj.aedToUsd);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetalPriceSnapshotAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
