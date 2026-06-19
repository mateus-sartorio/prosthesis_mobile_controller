import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../config/mqtt_config.dart';
import '../services/mqtt_service.dart';
import '../models/action_command.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late MqttService _mqttService;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isRunning = false;
  GaitMode? _activeMode;

  static const _modeConfig = <GaitMode, ({IconData icon, Color color})>{
    GaitMode.walking: (
      icon: Icons.directions_walk_rounded,
      color: Color(0xFF2563EB),
    ),
    GaitMode.stairAscent: (icon: Icons.north_rounded, color: Color(0xFF7C3AED)),
    GaitMode.standing: (
      icon: Icons.accessibility_new_rounded,
      color: Color(0xFF059669),
    ),
    GaitMode.stairDescent: (
      icon: Icons.south_rounded,
      color: Color(0xFFDB2777),
    ),
    GaitMode.upslopeWalking: (
      icon: Icons.trending_up_rounded,
      color: Color(0xFFD97706),
    ),
    GaitMode.downslopeWalking: (
      icon: Icons.trending_down_rounded,
      color: Color(0xFF0891B2),
    ),
    GaitMode.sitting: (
      icon: Icons.airline_seat_recline_normal_rounded,
      color: Color(0xFF65A30D),
    ),
    GaitMode.sitToStand: (icon: Icons.upload_rounded, color: Color(0xFFEA580C)),
    GaitMode.standToSit: (
      icon: Icons.download_rounded,
      color: Color(0xFF6D28D9),
    ),
  };

  @override
  void initState() {
    super.initState();
    _initializeMqtt();
  }

  Future<void> _initializeMqtt() async {
    _mqttService = MqttService();
    _mqttService.connectionStatusStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
        _isConnecting = false;
      });
    });
    await _connectMqtt();
  }

  Future<void> _connectMqtt() async {
    setState(() => _isConnecting = true);
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

  Future<void> _toggleRunning() async {
    final newRunning = !_isRunning;
    final powerState = newRunning ? PowerState.on : PowerState.off;
    try {
      await _mqttService.publishAction(
        powerState.value,
        type: CommandType.power,
      );
      setState(() => _isRunning = newRunning);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newRunning ? 'Started' : 'Stopped'),
            duration: const Duration(seconds: 1),
            backgroundColor: newRunning
                ? const Color(0xFF22C55E)
                : const Color(0xFFEF4444),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send command: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleModeSelect(GaitMode mode) async {
    try {
      await _mqttService.publishAction(mode.value);
      setState(() => _activeMode = mode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${mode.label} activated'),
            duration: const Duration(seconds: 1),
            backgroundColor: _modeConfig[mode]!.color,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send command: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatusBar(AppLocalizations l10n) {
    final statusColor = _isConnected
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
    final statusText = _isConnecting
        ? l10n.connecting
        : (_isConnected ? l10n.connected : l10n.disconnected);

    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 8,
            height: 8,
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
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            MqttConfig.commandLogsTopic,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF94A3B8),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(GaitMode mode) {
    final cfg = _modeConfig[mode]!;
    final isActive = _activeMode == mode;
    final enabled = _isConnected;

    return GestureDetector(
      onTap: enabled ? () => _handleModeSelect(mode) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive ? cfg.color : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? cfg.color
                : enabled
                ? const Color(0xFF334155)
                : const Color(0xFF1E293B),
            width: 1.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: cfg.color.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  cfg.icon,
                  size: 28,
                  color: isActive ? Colors.white : cfg.color,
                ),
                const SizedBox(height: 8),
                Text(
                  mode.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : const Color(0xFFCBD5E1),
                    height: 1.3,
                  ),
                ),
              ],
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
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Prothesis Controller',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1E293B)),
        ),
      ),
      body: Column(
        children: [
          _buildStatusBar(l10n),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16, top: 4),
                      child: ElevatedButton.icon(
                        onPressed: _toggleRunning,
                        icon: Icon(
                          _isRunning
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          _isRunning ? 'Stop' : 'Start',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRunning
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 36,
                            vertical: 20,
                          ),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, top: 4),
                    child: Text(
                      _activeMode != null
                          ? 'Active: ${_activeMode!.label}'
                          : 'Select a gait mode',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.9,
                      children: GaitMode.values.map(_buildModeCard).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!_isConnected && !_isConnecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _connectMqtt,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(
                    'Reconnect',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
