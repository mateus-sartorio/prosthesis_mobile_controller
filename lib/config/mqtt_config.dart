import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'utils.dart';

/// MQTT configuration loaded from an environment-specific JSON file.
class MqttConfig {
  static String _environment = 'dev';
  static String _host = '10.0.2.2';
  static int _port = 1883;
  static String? _username;
  static String? _password;
  static String _commandLogsTopic = 'prothesis/actions';
  static int _qos = 1;
  static String _clientId = 'prothesis-mobile-controller';
  static Duration _connectionTimeout = const Duration(seconds: 15);
  static Duration _reconnectInterval = const Duration(seconds: 5);
  static int _maxReconnectAttempts = 10;

  static String get environment => _environment;
  static String get host => _host;
  static int get port => _port;
  static String? get username => _username;
  static String? get password => _password;
  static String get commandLogsTopic => _commandLogsTopic;
  static int get qos => _qos;
  static String get clientId => _clientId;
  static Duration get connectionTimeout => _connectionTimeout;
  static Duration get reconnectInterval => _reconnectInterval;
  static int get maxReconnectAttempts => _maxReconnectAttempts;

  static Future<void> load({String? environment}) async {
    final selectedEnvironment =
        (environment ??
                const String.fromEnvironment('APP_ENV', defaultValue: 'dev'))
            .trim();
    final assetPath = 'assets/config/$selectedEnvironment.json';

    String jsonString;
    try {
      jsonString = await rootBundle.loadString(assetPath);
    } on FlutterError catch (error) {
      throw FlutterError(
        'Unable to load MQTT config for environment "$selectedEnvironment" from $assetPath. '
        'Check that the file exists and is declared in pubspec.yaml. '
        'Original error: ${error.message}',
      );
    }

    final decoded = json.decode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'MQTT config file "$assetPath" must contain a JSON object.',
      );
    }

    _environment = selectedEnvironment;
    _host = readString(decoded, 'host', fallback: _host);
    _port = readInt(decoded, 'port', fallback: _port);
    _username = readNullableString(decoded, 'username');
    _password = readNullableString(decoded, 'password');
    _commandLogsTopic = readString(
      decoded,
      'commandLogsTopic',
      fallback: _commandLogsTopic,
    );
    _qos = readInt(decoded, 'qos', fallback: _qos);
    _clientId = readString(decoded, 'clientId', fallback: _clientId);
    _connectionTimeout = Duration(
      seconds: readInt(
        decoded,
        'connectionTimeoutSeconds',
        fallback: _connectionTimeout.inSeconds,
      ),
    );
    _reconnectInterval = Duration(
      seconds: readInt(
        decoded,
        'reconnectIntervalSeconds',
        fallback: _reconnectInterval.inSeconds,
      ),
    );
    _maxReconnectAttempts = readInt(
      decoded,
      'maxReconnectAttempts',
      fallback: _maxReconnectAttempts,
    );
  }
}
