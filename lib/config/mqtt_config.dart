import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'utils.dart';

class MqttConfig {
  static String _environment = 'dev';
  static String _host = '10.0.2.2';
  static int _port = 1883;
  static bool _useSSL = false;
  static const String _username = String.fromEnvironment('MQTT_USERNAME');
  static const String _password = String.fromEnvironment('MQTT_PASSWORD');
  static String _commandLogsTopic = 'prosthesis/actions';
  static String _validatedLogsTopic = 'prosthesis/logs/validated';
  static String _powerFeedbackValidatedTopic =
      'prosthesis/actions/feedback/validated';
  static int _qos = 1;
  static String _clientId = 'prosthesis-mobile-controller';
  static Duration _connectionTimeout = const Duration(seconds: 15);
  static Duration _reconnectInterval = const Duration(seconds: 5);
  static int _maxReconnectAttempts = 10;
  static Duration _powerFeedbackTimeout = const Duration(seconds: 10);

  static String get environment => _environment;
  static String get host => _host;
  static int get port => _port;
  static bool get useSSL => _useSSL;
  static String? get username => _username.isEmpty ? null : _username;
  static String? get password => _password.isEmpty ? null : _password;
  static String get commandLogsTopic => _commandLogsTopic;
  static String get validatedLogsTopic => _validatedLogsTopic;
  static String get powerFeedbackValidatedTopic => _powerFeedbackValidatedTopic;
  static int get qos => _qos;
  static String get clientId => _clientId;
  static Duration get connectionTimeout => _connectionTimeout;
  static Duration get reconnectInterval => _reconnectInterval;
  static int get maxReconnectAttempts => _maxReconnectAttempts;
  static Duration get powerFeedbackTimeout => _powerFeedbackTimeout;

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
    _useSSL = readBool(decoded, 'useSSL', fallback: _useSSL);
    _commandLogsTopic = readString(
      decoded,
      'commandLogsTopic',
      fallback: _commandLogsTopic,
    );
    _validatedLogsTopic = readString(
      decoded,
      'validatedLogsTopic',
      fallback: _validatedLogsTopic,
    );
    _powerFeedbackValidatedTopic = readString(
      decoded,
      'powerFeedbackValidatedTopic',
      fallback: _powerFeedbackValidatedTopic,
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
    _powerFeedbackTimeout = Duration(
      seconds: readInt(
        decoded,
        'powerFeedbackTimeoutSeconds',
        fallback: _powerFeedbackTimeout.inSeconds,
      ),
    );
  }
}
