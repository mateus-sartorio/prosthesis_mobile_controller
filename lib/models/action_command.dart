import 'dart:convert';

/// Command type definitions
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

/// Power states (turn the prosthesis on or off)
enum PowerState {
  on(16),
  off(17);

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

/// The actuator current setpoint, in milliamps. Unlike the other commands the
/// value is not an enum: it is the milliamp figure itself, sent as the
/// `value` of a [CommandType.actuatorCurrent] command.
abstract final class ActuatorCurrent {
  /// Bounds the prosthesis accepts. Values outside them are rejected by the
  /// bridge, so the UI never offers one and [clamp] is applied before sending.
  static const int minMilliamps = 3000;
  static const int maxMilliamps = 15000;

  /// Step between selectable values, in milliamps. Keeps the slider on round
  /// numbers instead of whatever pixel the finger landed on.
  static const int stepMilliamps = 100;

  /// The value assumed before the prosthesis has confirmed one. It cannot be
  /// queried, so the app starts from the weakest setting rather than claiming
  /// a current the actuator may not be running.
  static const int assumedInitialMilliamps = minMilliamps;

  /// Number of discrete positions between [minMilliamps] and [maxMilliamps].
  static const int divisions = (maxMilliamps - minMilliamps) ~/ stepMilliamps;

  /// [milliamps] rounded to the nearest [stepMilliamps] and held inside the
  /// accepted range.
  static int clamp(num milliamps) {
    final stepped = (milliamps / stepMilliamps).round() * stepMilliamps;
    return stepped.clamp(minMilliamps, maxMilliamps);
  }
}

/// Gait modes
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

  /// The gait mode with this wire value, or `null` when the value is not one
  /// the app knows about (a prosthesis newer than this app).
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
  final int commandType;
  final int value;

  CommandLog({
    this.id,
    DateTime? timestamp,
    required this.commandType,
    required this.value,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  factory CommandLog.fromGaitMode(GaitMode mode, {String? id}) {
    return CommandLog(
      id: id,
      commandType: CommandType.gaitMode.value,
      value: mode.value,
    );
  }

  factory CommandLog.fromPower(PowerState state, {String? id}) {
    return CommandLog(
      id: id,
      commandType: CommandType.power.value,
      value: state.value,
    );
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'command_type': commandType,
    'value': value,
  };

  String toJson() => jsonEncode(toMap());

  @override
  String toString() =>
      'CommandLog(id: $id, timestamp: $timestamp, commandType: $commandType, value: $value)';
}
