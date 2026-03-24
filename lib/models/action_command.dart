import 'dart:convert';

/// Model representing an MQTT action command
class ActionCommand {
  final int commandType;
  final int value;

  ActionCommand({
    required this.commandType,
    required this.value,
  });

  /// Convert to JSON map
  Map<String, dynamic> toMap() {
    return {
      'commandType': commandType,
      'value': value,
    };
  }

  /// Convert to JSON string
  String toJson() {
    return jsonEncode(toMap());
  }

  @override
  String toString() => 'ActionCommand(commandType: $commandType, value: $value)';
}
