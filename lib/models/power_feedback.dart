import 'dart:convert';

import 'action_command.dart';

/// Which power command a feedback message answers.
enum PowerCommand {
  powerOn('power_on'),
  powerOff('power_off');

  final String wireValue;
  const PowerCommand(this.wireValue);

  /// The power state this command asks the prosthesis to reach.
  PowerState get requestedState =>
      this == PowerCommand.powerOn ? PowerState.on : PowerState.off;

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

/// Whether the prosthesis ended up in the state the command asked for.
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

/// The prosthesis power state reported *after* a command was handled.
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

/// A power command feedback message published by the orchestrator on
/// `prosthesis/actions/feedback/parsed`.
///
/// Every power command (`16` / `17`) that reaches the prosthesis is answered
/// with exactly one of these. Unknown fields are ignored so a future
/// orchestrator version that forwards more data doesn't break parsing.
class PowerFeedback {
  final DateTime timestamp;
  final PowerCommand command;
  final PowerFeedbackStatus status;
  final ProsthesisState state;

  /// The gait mode the prosthesis is in *after* the command was handled, as
  /// the raw wire value. Kept raw because the bridge sends any `u8`: `0` while
  /// the prosthesis is off, and possibly a mode this app version predates.
  /// Use [gaitMode] for the resolved enum.
  final int gait;

  /// Human-readable detail from the bridge. Free text and **not** a stable
  /// API: show it and log it, never branch on it.
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

  /// [gait] as a known [GaitMode], or `null` when the reported value is not
  /// one (the prosthesis is off, or the bridge is newer than the app).
  GaitMode? get gaitMode => GaitMode.fromValue(gait);

  /// Parses a raw payload, returning `null` when it is malformed (missing
  /// required field, unknown enum value or invalid JSON). Callers should log
  /// and ignore a `null` rather than crash the MQTT callback.
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
