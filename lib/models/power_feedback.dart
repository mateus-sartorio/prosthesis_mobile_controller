import 'dart:convert';

import 'action_command.dart';

enum PowerCommand {
  powerOn('power_on'),
  powerOff('power_off'),
  setGait('set_gait'),
  setActuatorCurrent('set_actuator_current');

  final String wireValue;
  const PowerCommand(this.wireValue);

  PowerState? get requestedState => switch (this) {
    PowerCommand.powerOn => PowerState.on,
    PowerCommand.powerOff => PowerState.off,
    PowerCommand.setGait => null,
    PowerCommand.setActuatorCurrent => null,
  };

  static PowerCommand? fromWire(Object? value) {
    for (final command in PowerCommand.values) {
      if (command.wireValue == value) {
        return command;
      }
    }
    return null;
  }

  static PowerCommand forState(PowerState state) =>
      state == PowerState.on ? PowerCommand.powerOn : PowerCommand.powerOff;
}

enum PowerFeedbackStatus {
  success('success'),
  failure('failure');

  final String wireValue;
  const PowerFeedbackStatus(this.wireValue);

  bool get isSuccess => this == PowerFeedbackStatus.success;

  static PowerFeedbackStatus? fromWire(Object? value) {
    for (final status in PowerFeedbackStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return null;
  }
}

enum ProsthesisState {
  on('on'),
  off('off');

  final String wireValue;
  const ProsthesisState(this.wireValue);

  bool get isOn => this == ProsthesisState.on;

  static ProsthesisState? fromWire(Object? value) {
    for (final state in ProsthesisState.values) {
      if (state.wireValue == value) {
        return state;
      }
    }
    return null;
  }
}

class PowerFeedback {
  final DateTime timestamp;
  final PowerCommand command;
  final PowerFeedbackStatus status;
  final ProsthesisState state;

  final int gait;

  final String message;

  const PowerFeedback({
    required this.timestamp,
    required this.command,
    required this.status,
    required this.state,
    required this.gait,
    required this.message,
  });

  bool get isSuccess => status.isSuccess;

  GaitMode? get gaitMode => GaitMode.fromValue(gait);

  static PowerFeedback? tryParse(String payload) {
    Object? decoded;
    try {
      decoded = json.decode(payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final rawTimestamp = decoded['timestamp'];
    final timestamp = rawTimestamp is String
        ? DateTime.tryParse(rawTimestamp)
        : null;
    final command = PowerCommand.fromWire(decoded['command']);
    final status = PowerFeedbackStatus.fromWire(decoded['status']);
    final state = ProsthesisState.fromWire(decoded['state']);
    final gait = decoded['gait'];
    final message = decoded['message'];

    if (timestamp == null ||
        command == null ||
        status == null ||
        state == null ||
        gait is! int ||
        message is! String) {
      return null;
    }

    return PowerFeedback(
      timestamp: timestamp.toUtc(),
      command: command,
      status: status,
      state: state,
      gait: gait,
      message: message,
    );
  }

  @override
  String toString() =>
      'PowerFeedback(timestamp: $timestamp, command: ${command.wireValue}, '
      'status: ${status.wireValue}, state: ${state.wireValue}, '
      'gait: $gait, message: $message)';
}
