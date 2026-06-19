import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/mqtt_config.dart';
import '../models/action_command.dart';

/// Service for managing MQTT connection and publishing messages
class MqttService {
  MqttService({bool subscribeToParsedLogs = false})
    : _subscribeToParsedLogs = subscribeToParsedLogs;

  /// Whether this client should subscribe to the parsed-logs topic and emit
  /// the payloads on [parsedLogsStream]. Off by default so a publish-only
  /// client (e.g. the control screen) doesn't open a needless subscription.
  final bool _subscribeToParsedLogs;

  MqttServerClient? _client;
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _parsedLogsController = StreamController<String>.broadcast();
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  final String _runtimeClientId =
      '${MqttConfig.clientId}-${DateTime.now().millisecondsSinceEpoch}';

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isReconnecting = false;
  bool _manualDisconnect = false;
  bool _isDisposed = false;

  /// Stream of connection status changes
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  /// Stream of raw payloads received on the parsed-logs topic. Only emits when
  /// the client was created with `subscribeToParsedLogs: true`.
  Stream<String> get parsedLogsStream => _parsedLogsController.stream;

  /// Check if currently connected
  bool get isConnected => _isConnected;

  /// Initialize and connect to MQTT broker
  Future<void> connect() async {
    if (_isDisposed || _isConnecting || _isConnected) {
      return;
    }

    _isConnecting = true;
    _manualDisconnect = false;

    try {
      // Ensure previous client cannot trigger reconnect callbacks.
      _client?.onDisconnected = null;
      _client?.onConnected = null;
      _client?.disconnect();

      final client = MqttServerClient(MqttConfig.host, _runtimeClientId);
      client.port = MqttConfig.port;
      client.secure = MqttConfig.useSSL;
      client.keepAlivePeriod = 20;
      client.onConnected = _onConnected;
      client.onDisconnected = _onDisconnected;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(_runtimeClientId)
          .startClean();

      client.connectionMessage = connMessage;
      _client = client;

      await client
          .connect(MqttConfig.username, MqttConfig.password)
          .timeout(
            MqttConfig.connectionTimeout,
            onTimeout: () {
              throw Exception('Connection timeout');
            },
          );

      final status = client.connectionStatus?.state;
      if (status != MqttConnectionState.connected) {
        throw Exception('MQTT connect failed with state: $status');
      }
    } catch (e) {
      _isConnected = false;
      _connectionStatusController.add(false);
      debugPrint('MQTT Connection error: $e');
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  /// Disconnect from MQTT broker
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _isReconnecting = false;

    try {
      _client?.onDisconnected = null;
      _client?.disconnect();
      _isConnected = false;
      _connectionStatusController.add(false);
    } catch (e) {
      debugPrint('MQTT Disconnect error: $e');
    }
  }

  /// Publish an action command to the actions topic
  Future<void> publishAction(int value) async {
    if (!_isConnected || _client == null) {
      throw Exception('MQTT not connected');
    }

    try {
      final command = CommandLog(
        commandType: CommandType.gaitMode.value,
        value: value,
      );
      final payload = command.toJson();

      final builder = MqttClientPayloadBuilder()..addString(payload);

      _client!.publishMessage(
        MqttConfig.commandLogsTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: false,
      );

      debugPrint('Published: $payload to ${MqttConfig.commandLogsTopic}');
    } catch (e) {
      debugPrint('MQTT Publish error: $e');
      rethrow;
    }
  }

  /// Called when MQTT connects successfully
  void _onConnected() {
    debugPrint('MQTT Connected (clientId=$_runtimeClientId)');
    _isConnected = true;
    _isReconnecting = false;
    _connectionStatusController.add(true);

    if (_subscribeToParsedLogs) {
      _subscribeParsedLogs();
    }
  }

  /// Subscribes to the parsed-logs topic and wires the broker's update stream
  /// into [parsedLogsStream]. Called on every (re)connect because each connect
  /// builds a fresh client with its own `updates` stream.
  void _subscribeParsedLogs() {
    final client = _client;
    if (client == null) {
      return;
    }

    client.subscribe(MqttConfig.parsedLogsTopic, MqttQos.atLeastOnce);

    // Drop any listener bound to a previous (now-dead) client before binding
    // to the current one, so we never leak or double-handle messages.
    _updatesSub?.cancel();
    _updatesSub = client.updates?.listen(_onMessages);
  }

  /// Handles a batch of incoming MQTT messages, forwarding parsed-logs payloads
  /// to [parsedLogsStream].
  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final received in messages) {
      if (received.topic != MqttConfig.parsedLogsTopic) {
        continue;
      }
      final publishMessage = received.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        publishMessage.payload.message,
      );
      if (!_parsedLogsController.isClosed) {
        _parsedLogsController.add(payload);
      }
    }
  }

  /// Called when MQTT disconnects
  void _onDisconnected() {
    final status = _client?.connectionStatus;
    debugPrint(
      'MQTT Disconnected '
      '(origin=${status?.disconnectionOrigin}, code=${status?.returnCode})',
    );
    _isConnected = false;
    _connectionStatusController.add(false);

    // Reconnect only when disconnect wasn't intentional.
    if (!_manualDisconnect && !_isDisposed) {
      _attemptReconnect();
    }
  }

  /// Attempt to reconnect with exponential backoff
  Future<void> _attemptReconnect() async {
    if (_isReconnecting || _isDisposed || _manualDisconnect) {
      return;
    }

    _isReconnecting = true;
    int attempts = 0;
    while (attempts < MqttConfig.maxReconnectAttempts &&
        !_isConnected &&
        !_manualDisconnect &&
        !_isDisposed) {
      await Future.delayed(
        Duration(seconds: (attempts + 1) * 2), // Exponential backoff
      );
      try {
        debugPrint('Attempting to reconnect... (attempt ${attempts + 1})');
        await connect();
        if (_isConnected) {
          break;
        }
      } catch (e) {
        attempts++;
        debugPrint('Reconnection attempt failed: $e');
      }
    }
    _isReconnecting = false;
  }

  /// Clean up resources
  void dispose() {
    _isDisposed = true;
    _manualDisconnect = true;
    _isReconnecting = false;
    _updatesSub?.cancel();
    _client?.onDisconnected = null;
    _client?.onConnected = null;
    _client?.disconnect();

    _connectionStatusController.close();
    _parsedLogsController.close();
    _isConnected = false;
  }
}
