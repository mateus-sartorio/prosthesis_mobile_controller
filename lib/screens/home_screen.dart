import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../config/mqtt_config.dart';
import '../services/mqtt_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late MqttService _mqttService;
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _initializeMqtt();
  }

  /// Initialize MQTT service and connect
  Future<void> _initializeMqtt() async {
    _mqttService = MqttService();

    // Listen to connection status changes
    _mqttService.connectionStatusStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
        _isConnecting = false;
      });
    });

    // Attempt to connect
    await _connectMqtt();
  }

  /// Connect to MQTT broker
  Future<void> _connectMqtt() async {
    setState(() {
      _isConnecting = true;
    });

    try {
      await _mqttService.connect();
      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle Levantar button press
  Future<void> _handleLevantar() async {
    try {
      await _mqttService.publishAction(1);
      _showActionFeedback('Levantar');
    } catch (e) {
      _showErrorSnackBar('Failed to publish action: $e');
    }
  }

  /// Handle Andar button press
  Future<void> _handleAndar() async {
    try {
      await _mqttService.publishAction(2);
      _showActionFeedback('Andar');
    } catch (e) {
      _showErrorSnackBar('Failed to publish action: $e');
    }
  }

  /// Handle Subir Escada button press
  Future<void> _handleSubirEscada() async {
    try {
      await _mqttService.publishAction(3);
      _showActionFeedback('Subir Escada');
    } catch (e) {
      _showErrorSnackBar('Failed to publish action: $e');
    }
  }

  /// Show feedback after action
  void _showActionFeedback(String action) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$action sent successfully'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Build connection status indicator
  Widget _buildStatusBar(AppLocalizations l10n) {
    final statusColor = _isConnected ? Colors.green : Colors.red;
    final statusText = _isConnecting
        ? l10n.connecting
        : (_isConnected ? l10n.connected : l10n.disconnected);

    return Container(
      color: const Color(0xFFE2E8F0),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.connectionStatus,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.topic,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Expanded(
                child: Text(
                  MqttConfig.actionsTopic,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build action button
  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
    required IconData icon,
    required Color iconColor,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ElevatedButton.icon(
          onPressed: _isConnected ? onPressed : null,
          icon: Icon(
            icon,
            size: 20,
            color: _isConnected ? iconColor : Colors.grey[600],
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: Colors.grey[300],
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1,
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _isConnected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mqttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prothesis Mobile Controller'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(l10n),

          // Main content
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Instruction text
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Text(
                    l10n.instruction,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Levantar button
                      Row(
                        children: [
                          _buildActionButton(
                            label: l10n.levantar,
                            onPressed: _handleLevantar,
                            color: const Color(0xFF475569),
                            icon: Icons.arrow_upward_rounded,
                            iconColor: const Color(0xFF93C5FD),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Andar button
                      Row(
                        children: [
                          _buildActionButton(
                            label: l10n.andar,
                            onPressed: _handleAndar,
                            color: const Color(0xFF4B5563),
                            icon: Icons.directions_walk_rounded,
                            iconColor: const Color(0xFF86EFAC),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Subir Escada button
                      Row(
                        children: [
                          _buildActionButton(
                            label: l10n.subir_escada,
                            onPressed: _handleSubirEscada,
                            color: const Color(0xFF52525B),
                            icon: Icons.stairs_rounded,
                            iconColor: const Color(0xFFF9A8D4),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Reconnect button (shown when disconnected)
          if (!_isConnected && !_isConnecting)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _connectMqtt,
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
