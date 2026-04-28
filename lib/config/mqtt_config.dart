/// MQTT Configuration Constants
class MqttConfig {
  // Broker connection settings
  // Note: Use 10.0.2.2 for Android emulator (refers to host machine)
  // Use actual machine IP or 192.168.x.x for physical devices
  // Use localhost for iOS simulator or desktop
  static const String host = '10.0.2.2';
  static const int port = 1883;
  static const String? username = null;
  static const String? password = null;

  // MQTT Topics
  static const String commandLogsTopic = 'prothesis/actions';

  // MQTT Settings
  static const int qos = 1;
  static const String clientId = 'prothesis-mobile-controller';

  // Connection settings
  static const Duration connectionTimeout = Duration(seconds: 15);
  static const Duration reconnectInterval = Duration(seconds: 5);
  static const int maxReconnectAttempts = 10;
}
