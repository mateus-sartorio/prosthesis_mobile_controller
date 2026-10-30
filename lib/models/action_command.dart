import 'dart:convert';

enum CommandType { gaitMode, power, actuatorCurrent }

extension CommandTypeValue on CommandType {
  int get value {
    switch (this) {
      case CommandType.gaitMode:
        return 1;
      case CommandType.power:
        return 2;
      case CommandType.actuatorCurrent:
        return 3;
    }
  }
}

enum PowerState {
  on(1),
  off(2);

  final int value;
  const PowerState(this.value);

  String get label {
    switch (this) {
      case PowerState.on:
        return 'On';
      case PowerState.off:
        return 'Off';
    }
  }
}

abstract final class ActuatorCurrent {
  static const int minMilliamps = 3000;
  static const int maxMilliamps = 15000;

  static const int stepMilliamps = 100;

  static const int assumedInitialMilliamps = minMilliamps;

  static const int divisions = (maxMilliamps - minMilliamps) ~/ stepMilliamps;

  static int clamp(num milliamps) {
    final stepped = (milliamps / stepMilliamps).round() * stepMilliamps;
    return stepped.clamp(minMilliamps, maxMilliamps);
  }
}

enum GaitMode {
  walking(1),
  stairAscent(2),
  standing(3),
  stairDescent(4),
  upslopeWalking(5),
  downslopeWalking(6),
  sitting(7),
  sitToStand(8),
  standToSit(9);

  final int value;
  const GaitMode(this.value);

  String get label {
    switch (this) {
      case GaitMode.walking:
        return 'Walking';
      case GaitMode.stairAscent:
        return 'Stair Ascent';
      case GaitMode.standing:
        return 'Standing';
      case GaitMode.stairDescent:
        return 'Stair Descent';
      case GaitMode.upslopeWalking:
        return 'Upslope Walking';
      case GaitMode.downslopeWalking:
        return 'Downslope Walking';
      case GaitMode.sitting:
        return 'Sitting';
      case GaitMode.sitToStand:
        return 'Sit to Stand';
      case GaitMode.standToSit:
        return 'Stand to Sit';
    }
  }

  static GaitMode? fromValue(Object? value) {
    for (final mode in GaitMode.values) {
      if (mode.value == value) {
        return mode;
      }
    }
    return null;
  }
}

class CommandLog {
  final String? id;
  final DateTime timestamp;
  final CommandType commandType;
  final int value;

  CommandLog({this.id, DateTime? timestamp, required this.commandType, required this.value})
    : timestamp = (timestamp ?? DateTime.now()).toUtc();

  factory CommandLog.fromGaitMode(GaitMode mode, {String? id}) {
    return CommandLog(id: id, commandType: CommandType.gaitMode, value: mode.value);
  }

  factory CommandLog.fromPower(PowerState state, {String? id}) {
    return CommandLog(id: id, commandType: CommandType.power, value: state.value);
  }

  factory CommandLog.fromActuatorCurrent(int milliamps, {String? id}) {
    return CommandLog(id: id, commandType: CommandType.actuatorCurrent, value: milliamps);
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'command_type': commandType.value,
    'value': value,
  };

  String toJson() => jsonEncode(toMap());

  @override
  String toString() => 'CommandLog(id: $id, timestamp: $timestamp, commandType: ${commandType.value}, value: $value)';
}
