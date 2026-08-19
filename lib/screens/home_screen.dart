import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../config/mqtt_config.dart';
import '../services/mqtt_service.dart';
import '../models/action_command.dart';
import '../models/power_feedback.dart';

/// What the UI knows about the prosthesis power state.
///
/// The prosthesis cannot be queried, so the app starts from the assumed
/// [_HomeScreenState._assumedInitialState] ([off]) and only reaches [unknown]
/// when a command it sent went unanswered.
enum PowerUiState { unknown, pending, on, off }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late MqttService _mqttService;
  bool _isConnected = false;
  bool _isConnecting = false;
  PowerUiState _powerState = _assumedInitialState;
  PowerCommand? _pendingCommand;
  Timer? _feedbackTimer;
  StreamSubscription<PowerFeedback>? _feedbackSub;
  PowerFeedback? _lastFeedback;
  GaitMode? _activeMode;

  /// The power state assumed before any feedback has been received. There is
  /// no way to query the prosthesis, so the app assumes it starts off instead
  /// of showing a neutral state.
  static const _assumedInitialState = PowerUiState.off;

  /// Which command the single power button sends, or `null` when the state is
  /// unknown and both commands should be offered instead. While a command is
  /// pending the button keeps showing that command, disabled.
  PowerState? get _commandButtonTarget {
    switch (_powerState) {
      case PowerUiState.unknown:
        return null;
      case PowerUiState.pending:
        return _pendingCommand?.requestedState;
      case PowerUiState.on:
        return PowerState.off;
      case PowerUiState.off:
        return PowerState.on;
    }
  }

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
    _mqttService = MqttService(subscribeToPowerFeedback: true);
    _mqttService.connectionStatusStream.listen((isConnected) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isConnected = isConnected;
        _isConnecting = false;
      });
      if (!isConnected) {
        // Feedback produced while we are offline is lost, so anything we
        // believed about the power state can no longer be trusted.
        _resetPowerState();
      }
    });
    _feedbackSub = _mqttService.powerFeedbackStream.listen(_onPowerFeedback);
    await _connectMqtt();
  }

  /// Drops any in-flight command and falls back to a state we can defend:
  /// once feedback has been seen, missing it makes the state genuinely
  /// unknown; before that the app stays on the assumed initial state.
  void _resetPowerState() {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingCommand = null;
      _powerState = _lastFeedback == null
          ? _assumedInitialState
          : PowerUiState.unknown;
    });
  }

  /// Applies a feedback message. Feedback is the only writer of the power
  /// state: the toggle is never flipped optimistically when publishing.
  void _onPowerFeedback(PowerFeedback feedback) {
    if (!mounted) {
      return;
    }

    final pending = _pendingCommand;
    if (pending != null && pending != feedback.command) {
      // Not the answer we are waiting for (stale, or another controller's
      // command). Keep waiting for ours rather than settling on this one.
      debugPrint('Ignoring unmatched power feedback: $feedback');
      return;
    }

    _feedbackTimer?.cancel();
    _feedbackTimer = null;

    setState(() {
      _pendingCommand = null;
      _lastFeedback = feedback;
      _powerState = feedback.state.isOn ? PowerUiState.on : PowerUiState.off;
    });

    _showSnackBar(
      feedback.isSuccess
          ? '${feedback.state.isOn ? 'Started' : 'Stopped'}: ${feedback.message}'
          : 'Command failed: ${feedback.message}',
      feedback.isSuccess ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
      duration: feedback.isSuccess
          ? const Duration(seconds: 3)
          : const Duration(seconds: 6),
    );
  }

  /// No answer within the timeout: the prosthesis state is unknown, not the
  /// state we asked for.
  void _onFeedbackTimeout() {
    _feedbackTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingCommand = null;
      _powerState = PowerUiState.unknown;
    });
    _showSnackBar(
      'No response from prosthesis - power state unknown',
      const Color(0xFFF59E0B),
      duration: const Duration(seconds: 4),
    );
  }

  void _showSnackBar(
    String message,
    Color background, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: background,
      ),
    );
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

  /// Publishes a power command and waits for its feedback. Only one power
  /// command is ever in flight: feedback carries no correlation id, so
  /// matching relies on that discipline.
  Future<void> _sendPowerCommand(PowerState powerState) async {
    if (_pendingCommand != null || !_isConnected) {
      return;
    }

    setState(() {
      _pendingCommand = PowerCommand.forState(powerState);
      _powerState = PowerUiState.pending;
    });

    try {
      await _mqttService.publishAction(
        powerState.value,
        type: CommandType.power,
      );
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(
        MqttConfig.powerFeedbackTimeout,
        _onFeedbackTimeout,
      );
    } catch (e) {
      // The command never left the phone, so no feedback is coming.
      _resetPowerState();
      _showSnackBar('Failed to send command: $e', Colors.red);
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

  /// Label and color for the current power state. [PowerUiState.unknown] is a
  /// real, neutral state - never rendered as "off".
  ({String label, Color color, IconData icon}) get _powerStatePresentation {
    switch (_powerState) {
      case PowerUiState.on:
        return (
          label: 'Prosthesis on',
          color: const Color(0xFF22C55E),
          icon: Icons.power_settings_new_rounded,
        );
      case PowerUiState.off:
        return (
          label: 'Prosthesis off',
          color: const Color(0xFFEF4444),
          icon: Icons.power_off_rounded,
        );
      case PowerUiState.pending:
        return (
          label: _pendingCommand == PowerCommand.powerOn
              ? 'Starting...'
              : 'Stopping...',
          color: const Color(0xFF38BDF8),
          icon: Icons.hourglass_top_rounded,
        );
      case PowerUiState.unknown:
        return (
          label: 'Power state unknown',
          color: const Color(0xFF94A3B8),
          icon: Icons.help_outline_rounded,
        );
    }
  }

  Widget _buildPowerButton({
    required PowerState target,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isPending = _powerState == PowerUiState.pending;
    final enabled = _isConnected && !isPending;

    return ElevatedButton.icon(
      onPressed: enabled ? () => _sendPowerCommand(target) : null,
      icon: isPending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF334155),
        disabledForegroundColor: const Color(0xFF94A3B8),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        shape: const StadiumBorder(),
      ),
    );
  }

  /// The power controls: a state chip, the command button(s) and the last
  /// feedback message. While the state is unknown both commands are offered,
  /// since there is nothing to toggle away from.
  Widget _buildPowerSection() {
    final presentation = _powerStatePresentation;
    final buttonTarget = _commandButtonTarget;

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16, top: 4),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: presentation.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: presentation.color.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(presentation.icon, size: 16, color: presentation.color),
                  const SizedBox(width: 6),
                  Text(
                    presentation.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: presentation.color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (buttonTarget == null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: _buildPowerButton(
                      target: PowerState.on,
                      label: 'Start',
                      icon: Icons.play_arrow_rounded,
                      color: const Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: _buildPowerButton(
                      target: PowerState.off,
                      label: 'Stop',
                      icon: Icons.stop_rounded,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ],
              )
            else
              _buildPowerButton(
                target: buttonTarget,
                label: buttonTarget == PowerState.on ? 'Start' : 'Stop',
                icon: buttonTarget == PowerState.on
                    ? Icons.play_arrow_rounded
                    : Icons.stop_rounded,
                color: buttonTarget == PowerState.on
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFEF4444),
              )
          ],
        ),
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
    _feedbackTimer?.cancel();
    _feedbackSub?.cancel();
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
          'Prosthesis Controller',
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
                  _buildPowerSection(),
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
