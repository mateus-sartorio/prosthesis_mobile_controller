import 'dart:convert';

/// Command type definitions
enum CommandType { gaitMode, power }

extension CommandTypeValue on CommandType {
  int get value {
    switch (this) {
      case CommandType.gaitMode:
        return 1;
      case CommandType.power:
        return 2;
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
