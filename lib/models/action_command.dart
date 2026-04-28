import 'dart:convert';

/// Command type definitions
enum CommandType { gaitMode }

extension CommandTypeValue on CommandType {
  int get value {
    switch (this) {
      case CommandType.gaitMode:
        return 1;
    }
  }
}

/// Gait modes
enum GaitMode {
  standUp(1),
  walk(2),
  climbStairs(3);

  final int value;
  const GaitMode(this.value);

  String buildGaitModeActionMessage() {
    final modeName = name.replaceAll('_', ' ').toLowerCase();
    final title = modeName.split(' ').map((s) => s[0].toUpperCase() + s.substring(1)).join(' ');
    return 'Gait mode changed to $title';
  }
}

/// Model representing a command log ready to be sent to MQTT.
/// The payload sent to MQTT will match the consumer's expected keys:
/// `{ "timestamp": <ISO8601>, "command_type": <int>, "value": <int> }`
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

  /// Helper factory for gait-mode commands
  factory CommandLog.fromGaitMode(GaitMode mode, {String? id}) {
    return CommandLog(id: id, commandType: CommandType.gaitMode.value, value: mode.value);
  }

  /// Map representation matching the receiver/parser expectations
  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'command_type': commandType,
        'value': value,
      };

  /// JSON string ready to publish to MQTT
  String toJson() => jsonEncode(toMap());

  @override
  String toString() => 'CommandLog(id: $id, timestamp: $timestamp, commandType: $commandType, value: $value)';
}
