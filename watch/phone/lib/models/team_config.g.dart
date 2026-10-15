// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TeamConfigAdapter extends TypeAdapter<TeamConfig> {
  @override
  final int typeId = 1;

  @override
  TeamConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TeamConfig(
      teamAName: fields[0] as String,
      teamBName: fields[1] as String,
      teamAColorHex: fields[2] as String,
      teamBColorHex: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, TeamConfig obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.teamAName)
      ..writeByte(1)
      ..write(obj.teamBName)
      ..writeByte(2)
      ..write(obj.teamAColorHex)
      ..writeByte(3)
      ..write(obj.teamBColorHex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
