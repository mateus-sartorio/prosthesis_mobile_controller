import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/mqtt_config.dart';
import '../models/action_command.dart';
import '../models/power_feedback.dart';

class MqttService {
  MqttService({bool subscribeToValidatedLogs = false, bool subscribeToPowerFeedback = false})
    : _subscribeToValidatedLogs = subscribeToValidatedLogs,
      _subscribeToPowerFeedback = subscribeToPowerFeedback;

  final bool _subscribeToValidatedLogs;

  final bool _subscribeToPowerFeedback;

  MqttServerClient? _client;
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _validatedLogsController = StreamController<String>.broadcast();
  final _powerFeedbackController = StreamController<PowerFeedback>.broadcast();
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  final String _runtimeClientId = '${MqttConfig.clientId}-${DateTime.now().millisecondsSinceEpoch}';

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isReconnecting = false;
  bool _manualDisconnect = false;
  bool _isDisposed = false;

  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  Stream<String> get validatedLogsStream => _validatedLogsController.stream;

  Stream<PowerFeedback> get powerFeedbackStream => _powerFeedbackController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isDisposed || _isConnecting || _isConnected) {
      return;
    }

    _isConnecting = true;
    _manualDisconnect = false;

    try {
      _client?.onDisconnected = null;
      _client?.onConnected = null;
      _client?.disconnect();

      final client = MqttServerClient(MqttConfig.host, _runtimeClientId);
      client.port = MqttConfig.port;
      client.secure = MqttConfig.useSSL;
      client.keepAlivePeriod = 20;
      client.onConnected = _onConnected;
      client.onDisconnected = _onDisconnected;

      final connMessage = MqttConnectMessage().withClientIdentifier(_runtimeClientId).startClean();

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

  Future<void> publishAction(CommandLog command) async {
    if (!_isConnected || _client == null) {
      throw Exception('MQTT not connected');
    }

    try {
      final payload = command.toJson();

      final builder = MqttClientPayloadBuilder()..addString(payload);

      _client!.publishMessage(MqttConfig.commandLogsTopic, MqttQos.atLeastOnce, builder.payload!, retain: false);

      debugPrint('Published: $payload to ${MqttConfig.commandLogsTopic}');
    } catch (e) {
      debugPrint('MQTT Publish error: $e');
      rethrow;
    }
  }

  void _onConnected() {
    debugPrint('MQTT Connected (clientId=$_runtimeClientId)');
    _isConnected = true;
    _isReconnecting = false;
    _connectionStatusController.add(true);

    _subscribeTopics();
  }

  void _subscribeTopics() {
    final client = _client;
    if (client == null || (!_subscribeToValidatedLogs && !_subscribeToPowerFeedback)) {
      return;
    }

    if (_subscribeToValidatedLogs) {
      client.subscribe(MqttConfig.validatedLogsTopic, MqttQos.atLeastOnce);
    }
    if (_subscribeToPowerFeedback) {
      client.subscribe(MqttConfig.powerFeedbackValidatedTopic, MqttQos.atLeastOnce);
    }

    _updatesSub?.cancel();
    _updatesSub = client.updates?.listen(_onMessages);
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final received in messages) {
      final topic = received.topic;
      if (topic != MqttConfig.validatedLogsTopic && topic != MqttConfig.powerFeedbackValidatedTopic) {
        continue;
      }
      final publishMessage = received.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(publishMessage.payload.message);

      if (topic == MqttConfig.validatedLogsTopic) {
        if (!_validatedLogsController.isClosed) {
          _validatedLogsController.add(payload);
        }
        continue;
      }

      final feedback = PowerFeedback.tryParse(payload);
      if (feedback == null) {
        debugPrint('Dropped malformed power feedback: $payload');
        continue;
      }
      debugPrint('Power feedback: $feedback');
      if (!_powerFeedbackController.isClosed) {
        _powerFeedbackController.add(feedback);
      }
    }
  }

  void _onDisconnected() {
    final status = _client?.connectionStatus;
    debugPrint(
      'MQTT Disconnected '
      '(origin=${status?.disconnectionOrigin}, code=${status?.returnCode})',
    );
    _isConnected = false;
    _connectionStatusController.add(false);

    if (!_manualDisconnect && !_isDisposed) {
      _attemptReconnect();
    }
  }

  Future<void> _attemptReconnect() async {
    if (_isReconnecting || _isDisposed || _manualDisconnect) {
      return;
    }

    _isReconnecting = true;
    int attempts = 0;
    while (attempts < MqttConfig.maxReconnectAttempts && !_isConnected && !_manualDisconnect && !_isDisposed) {
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

  void dispose() {
    _isDisposed = true;
    _manualDisconnect = true;
    _isReconnecting = false;
    _updatesSub?.cancel();
    _client?.onDisconnected = null;
    _client?.onConnected = null;
    _client?.disconnect();

    _connectionStatusController.close();
    _validatedLogsController.close();
    _powerFeedbackController.close();
    _isConnected = false;
  }
}
