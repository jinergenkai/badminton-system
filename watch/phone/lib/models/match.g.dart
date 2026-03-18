// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MatchAdapter extends TypeAdapter<Match> {
  @override
  final int typeId = 0;

  @override
  Match read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Match(
      id: fields[0] as String,
      teamAName: fields[1] as String,
      teamBName: fields[2] as String,
      teamAScore: fields[3] as int,
      teamBScore: fields[4] as int,
      winner: fields[5] as String,
      startTime: fields[6] as DateTime,
      endTime: fields[7] as DateTime,
      actionHistory: (fields[8] as List).cast<String>(),
      durationSeconds: fields[9] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Match obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.teamAName)
      ..writeByte(2)
      ..write(obj.teamBName)
      ..writeByte(3)
      ..write(obj.teamAScore)
      ..writeByte(4)
      ..write(obj.teamBScore)
      ..writeByte(5)
      ..write(obj.winner)
      ..writeByte(6)
      ..write(obj.startTime)
      ..writeByte(7)
      ..write(obj.endTime)
      ..writeByte(8)
      ..write(obj.actionHistory)
      ..writeByte(9)
      ..write(obj.durationSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
