import 'dart:convert';

import 'action_command.dart';

/// Which command a feedback message answers.
enum PowerCommand {
  powerOn('power_on'),
  powerOff('power_off'),
  setGait('set_gait');

  final String wireValue;
  const PowerCommand(this.wireValue);

  /// The power state this command asks the prosthesis to reach, or `null` for
  /// [setGait], which asks for a gait mode and leaves the power state alone.
  PowerState? get requestedState => switch (this) {
    PowerCommand.powerOn => PowerState.on,
    PowerCommand.powerOff => PowerState.off,
    PowerCommand.setGait => null,
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

/// A command feedback message published by the orchestrator on
/// `prosthesis/actions/feedback/parsed`.
///
/// Every command that reaches the prosthesis - power (`16` / `17`) and gait
/// (`1`..`9`) alike - is answered with exactly one of these. Unknown fields
/// are ignored so a future orchestrator version that forwards more data
/// doesn't break parsing.
class PowerFeedback {
  final DateTime timestamp;
  final PowerCommand command;
  final PowerFeedbackStatus status;
  final ProsthesisState state;

  /// The gait mode the prosthesis is in *after* the command was handled, as
  /// the raw wire value. Every feedback carries it, power commands included:
  /// the bridge always holds a gait mode, defaulting to `1` until a gait
  /// command changes it. Kept raw because the wire type is a `u8` and could
  /// name a mode this app version predates; use [gaitMode] for the enum.
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
  /// one this app knows (a bridge newer than the app). The orchestrator drops
  /// feedback whose gait it cannot resolve, so this is not expected in
  /// practice - it just must not crash the parse.
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
