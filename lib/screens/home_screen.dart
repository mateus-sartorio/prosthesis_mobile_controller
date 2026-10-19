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
/// [_HomeScreenState._assumedInitialState] ([off]) and falls back to it
/// whenever a command it sent goes unanswered. There is deliberately no
/// indeterminate state: anything the app cannot confirm is shown as [off].
enum PowerUiState { pending, on, off }

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

  /// The power command in flight, never [PowerCommand.setGait] - gait commands
  /// are tracked by [_pendingMode].
  PowerCommand? _pendingCommand;
  Timer? _feedbackTimer;
  StreamSubscription<PowerFeedback>? _feedbackSub;

  /// The gait mode the prosthesis last confirmed it is running, and the one a
  /// command is in flight for. Like the power state, [_activeMode] is only
  /// ever written from feedback.
  GaitMode? _activeMode;
  GaitMode? _pendingMode;
  Timer? _gaitFeedbackTimer;

  /// The actuator current the prosthesis last confirmed, in milliamps, and the
  /// value a command is in flight for. Like the power state,
  /// [_currentMilliamps] is only ever written from feedback.
  int _currentMilliamps = ActuatorCurrent.assumedInitialMilliamps;
  int? _pendingMilliamps;
  Timer? _currentFeedbackTimer;

  /// Where the slider's thumb sits. Follows the finger while dragging, so it
  /// runs ahead of [_currentMilliamps] until feedback confirms the setpoint
  /// (and snaps back to it when one is not confirmed).
  int _sliderMilliamps = ActuatorCurrent.assumedInitialMilliamps;

  /// True while any command is waiting for its feedback. Only one is ever in
  /// flight: the feedback's command id is assigned by the server, which the
  /// app never learns, so matching relies on that.
  bool get _isCommandPending =>
      _pendingCommand != null ||
      _pendingMode != null ||
      _pendingMilliamps != null;

  /// The power state assumed whenever the app has nothing confirmed to show:
  /// before any feedback has been received, and again after a command goes
  /// unanswered. There is no way to query the prosthesis, so it is assumed to
  /// be off rather than shown as indeterminate.
  static const _assumedInitialState = PowerUiState.off;

  /// Which command the single power button sends. While a command is pending
  /// the button keeps showing that command, disabled.
  PowerState get _commandButtonTarget {
    switch (_powerState) {
      case PowerUiState.pending:
        // A pending power state always carries its command; the fallback only
        // guards the impossible case, and matches the assumed-off state.
        return _pendingCommand?.requestedState ?? PowerState.on;
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
        if (!isConnected) {
          // Feedback produced while we are offline is lost, so the gait we
          // last saw confirmed cannot be trusted either.
          _activeMode = null;
        }
      });
      if (!isConnected) {
        // Feedback produced while we are offline is lost, so anything we
        // believed about the power state can no longer be trusted.
        _resetPendingCommands();
      }
    });
    _feedbackSub = _mqttService.powerFeedbackStream.listen(_onPowerFeedback);
    await _connectMqtt();
  }

  /// Drops any in-flight command and falls back to [_assumedInitialState]:
  /// with nothing confirmed, the prosthesis is treated as off. The actuator
  /// current goes back to its assumed default for the same reason - feedback
  /// missed while offline means the confirmed value can no longer be trusted.
  void _resetPendingCommands() {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _gaitFeedbackTimer?.cancel();
    _gaitFeedbackTimer = null;
    _currentFeedbackTimer?.cancel();
    _currentFeedbackTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingCommand = null;
      _pendingMode = null;
      _powerState = _assumedInitialState;
      _pendingMilliamps = null;
      _currentMilliamps = ActuatorCurrent.assumedInitialMilliamps;
      _sliderMilliamps = _currentMilliamps;
    });
  }

  /// Routes a feedback message to the handler for the command it answers.
  /// Feedback is the only writer of the power state and the active gait mode:
  /// neither is set optimistically when publishing.
  void _onPowerFeedback(PowerFeedback feedback) {
    if (!mounted) {
      return;
    }
    if (feedback.isInternal) {
      _onInternalFeedback(feedback);
      return;
    }
    switch (feedback.command) {
      case PowerCommand.setGait:
        _onGaitFeedback(feedback);
      case PowerCommand.setActuatorCurrent:
        _onCurrentFeedback(feedback);
      case PowerCommand.powerOn:
      case PowerCommand.powerOff:
        _onPowerCommandFeedback(feedback);
    }
  }

  /// Copies the prosthesis state a feedback reports into the UI state. Must be
  /// called from inside a [setState] callback.
  void _applyFeedback(PowerFeedback feedback) {
    _powerState = feedback.state.isOn ? PowerUiState.on : PowerUiState.off;
    // A gait only runs while the prosthesis is on, and a failed command leaves
    // it unclear which gait (if any) survived - both show as no active mode
    // rather than one that may not be running.
    _activeMode = feedback.isSuccess && feedback.state.isOn
        ? feedback.gaitMode
        : null;
    // The current the prosthesis reports running with replaces the assumed
    // one, unless the user is waiting on a setpoint of their own.
    final reportedCurrent = feedback.current;
    if (feedback.isSuccess && feedback.state.isOn && reportedCurrent != null) {
      _currentMilliamps = reportedCurrent;
      if (_pendingMilliamps == null) {
        _sliderMilliamps = reportedCurrent;
      }
    }
  }

  /// Applies something the prosthesis did on its own (a stop requested on the
  /// Raspberry Pi). It answers no command of ours, so whatever is pending keeps
  /// waiting for its own feedback.
  void _onInternalFeedback(PowerFeedback feedback) {
    setState(() {
      _applyFeedback(feedback);
    });

    _showSnackBar(
      feedback.isSuccess
          ? 'Stopped on the prosthesis: ${feedback.message}'
          : 'Stop on the prosthesis failed: ${feedback.message}',
      feedback.isSuccess ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
      duration: const Duration(seconds: 6),
    );
  }

  void _onPowerCommandFeedback(PowerFeedback feedback) {
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
      _applyFeedback(feedback);
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

  /// Applies the answer to a gait command. A feedback for the mode we asked
  /// for is ours whether it succeeded or not; one without a gait (the restart
  /// failed and left the prosthesis off) answers the pending command too.
  void _onGaitFeedback(PowerFeedback feedback) {
    final pending = _pendingMode;
    if (pending != null &&
        feedback.gait != null &&
        feedback.gaitMode != pending) {
      // Not the answer we are waiting for (stale, or another controller's
      // command). Keep waiting for ours rather than settling on this one.
      debugPrint('Ignoring unmatched gait feedback: $feedback');
      return;
    }

    _gaitFeedbackTimer?.cancel();
    _gaitFeedbackTimer = null;

    setState(() {
      _pendingMode = null;
      _applyFeedback(feedback);
    });

    final mode = feedback.gaitMode;
    _showSnackBar(
      feedback.isSuccess
          ? '${mode?.label ?? 'Gait ${feedback.gait}'} activated'
          : 'Gait change failed: ${feedback.message}',
      feedback.isSuccess
          ? (mode == null ? const Color(0xFF22C55E) : _modeConfig[mode]!.color)
          : const Color(0xFFEF4444),
      duration: feedback.isSuccess
          ? const Duration(seconds: 2)
          : const Duration(seconds: 6),
    );
  }

  /// Applies the answer to an actuator-current command. A success confirms the
  /// setpoint we asked for (or, when the feedback reports one, the current the
  /// prosthesis actually runs with); a failure leaves the prosthesis on the
  /// current it already had, so the slider goes back to that.
  void _onCurrentFeedback(PowerFeedback feedback) {
    final pending = _pendingMilliamps;

    _currentFeedbackTimer?.cancel();
    _currentFeedbackTimer = null;

    setState(() {
      _pendingMilliamps = null;
      // With no pending setpoint this is another controller's command (or a
      // stale one) and its new current is unknowable, so only the power and
      // gait state it reports are taken from it.
      if (pending != null && feedback.isSuccess) {
        _currentMilliamps = pending;
      }
      _sliderMilliamps = _currentMilliamps;
      _applyFeedback(feedback);
    });

    _showSnackBar(
      feedback.isSuccess
          ? 'Actuator current set to $_currentMilliamps mA'
          : 'Current change failed: ${feedback.message}',
      feedback.isSuccess ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
      duration: feedback.isSuccess
          ? const Duration(seconds: 2)
          : const Duration(seconds: 6),
    );
  }

  /// No answer within the timeout: the command is not confirmed, so the app
  /// falls back to assuming the prosthesis is off rather than showing the
  /// state we asked for.
  void _onFeedbackTimeout() {
    _feedbackTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingCommand = null;
      _powerState = _assumedInitialState;
    });
    _showSnackBar(
      'No response from prosthesis - assuming it is off',
      const Color(0xFFF59E0B),
      duration: const Duration(seconds: 4),
    );
  }

  /// No answer within the timeout: the requested mode may or may not be
  /// running, so no mode is shown as active rather than the one asked for.
  void _onGaitFeedbackTimeout() {
    _gaitFeedbackTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingMode = null;
      _activeMode = null;
    });
    _showSnackBar(
      'No response from prosthesis - gait mode unknown',
      const Color(0xFFF59E0B),
      duration: const Duration(seconds: 4),
    );
  }

  /// No answer within the timeout: the setpoint may or may not have been
  /// taken, so the slider returns to the last value the prosthesis confirmed.
  void _onCurrentFeedbackTimeout() {
    _currentFeedbackTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingMilliamps = null;
      _sliderMilliamps = _currentMilliamps;
    });
    _showSnackBar(
      'No response from prosthesis - actuator current unchanged',
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

  /// Publishes a power command and waits for its feedback. Only one command is
  /// ever in flight: feedback carries no correlation id, so matching relies on
  /// that discipline.
  Future<void> _sendPowerCommand(PowerState powerState) async {
    if (_isCommandPending || !_isConnected) {
      return;
    }

    setState(() {
      _pendingCommand = PowerCommand.forState(powerState);
      _powerState = PowerUiState.pending;
    });

    try {
      await _mqttService.publishAction(CommandLog.fromPower(powerState));
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(
        MqttConfig.powerFeedbackTimeout,
        _onFeedbackTimeout,
      );
    } catch (e) {
      // The command never left the phone, so no feedback is coming.
      _resetPendingCommands();
      _showSnackBar('Failed to send command: $e', Colors.red);
    }
  }

  /// Publishes a gait command and waits for its feedback, the same way
  /// [_sendPowerCommand] does: the card is never highlighted optimistically,
  /// and only one command is in flight at a time.
  Future<void> _handleModeSelect(GaitMode mode) async {
    if (_isCommandPending || !_isConnected) {
      return;
    }

    setState(() => _pendingMode = mode);

    try {
      await _mqttService.publishAction(CommandLog.fromGaitMode(mode));
      _gaitFeedbackTimer?.cancel();
      _gaitFeedbackTimer = Timer(
        MqttConfig.powerFeedbackTimeout,
        _onGaitFeedbackTimeout,
      );
    } catch (e) {
      // The command never left the phone, so no feedback is coming.
      _gaitFeedbackTimer?.cancel();
      _gaitFeedbackTimer = null;
      if (!mounted) {
        return;
      }
      setState(() => _pendingMode = null);
      _showSnackBar('Failed to send command: $e', Colors.red);
    }
  }

  /// Publishes an actuator-current setpoint and waits for its feedback, the
  /// same way [_sendPowerCommand] does: [_currentMilliamps] is never moved
  /// optimistically, and only one command is in flight at a time.
  Future<void> _sendCurrentCommand(int milliamps) async {
    final target = ActuatorCurrent.clamp(milliamps);

    if (_isCommandPending || !_isConnected) {
      // The slider is disabled in both cases, so this only guards a drag that
      // was already under way when the state changed: put the thumb back.
      setState(() => _sliderMilliamps = _currentMilliamps);
      return;
    }
    if (target == _currentMilliamps) {
      return;
    }

    setState(() => _pendingMilliamps = target);

    try {
      await _mqttService.publishAction(
        CommandLog.fromActuatorCurrent(target),
      );
      _currentFeedbackTimer?.cancel();
      _currentFeedbackTimer = Timer(
        MqttConfig.powerFeedbackTimeout,
        _onCurrentFeedbackTimeout,
      );
    } catch (e) {
      // The command never left the phone, so no feedback is coming.
      _currentFeedbackTimer?.cancel();
      _currentFeedbackTimer = null;
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingMilliamps = null;
        _sliderMilliamps = _currentMilliamps;
      });
      _showSnackBar('Failed to send command: $e', Colors.red);
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

  /// Label and color for the current power state.
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
    }
  }

  Widget _buildPowerButton({
    required PowerState target,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isPending = _powerState == PowerUiState.pending;
    final enabled = _isConnected && !_isCommandPending;

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
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        shape: const StadiumBorder(),
      ),
    );
  }

  /// The power controls: a state chip and the single command button that
  /// toggles away from the current state.
  Widget _buildPowerSection() {
    final presentation = _powerStatePresentation;
    final buttonTarget = _commandButtonTarget;

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14, top: 4),
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
            const SizedBox(height: 12),
            _buildPowerButton(
              target: buttonTarget,
              label: buttonTarget == PowerState.on ? 'Start' : 'Stop',
              icon: buttonTarget == PowerState.on
                  ? Icons.play_arrow_rounded
                  : Icons.stop_rounded,
              color: buttonTarget == PowerState.on
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
            ),
          ],
        ),
      ),
    );
  }

  /// The actuator current setpoint: a readout and a slider over the range the
  /// prosthesis accepts. The command is sent once, when the drag ends, rather
  /// than on every pixel of movement.
  Widget _buildCurrentSection() {
    final pending = _pendingMilliamps;
    final enabled = _isConnected && !_isCommandPending;
    final accent = pending != null
        ? const Color(0xFF38BDF8)
        : const Color(0xFF2563EB);

    // The inset is on the section as a whole so the heading, the readout and
    // the bound labels all line up with the ends of the track.
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
              const Text(
                'Actuator current',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const Spacer(),
              Text(
                pending != null
                    ? 'Setting $pending mA...'
                    : '$_sliderMilliamps mA',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: enabled || pending != null
                      ? accent
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              // The slider's own 48px tap slab is more height than the
              // screen can spare; the row above it keeps the control easy to
              // find, and the section's inset keeps the thumb off the edges.
              padding: EdgeInsets.zero,
              trackHeight: 4,
              activeTrackColor: accent,
              inactiveTrackColor: const Color(0xFF1E293B),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.15),
              valueIndicatorColor: accent,
              disabledActiveTrackColor: const Color(0xFF334155),
              disabledInactiveTrackColor: const Color(0xFF1E293B),
              disabledThumbColor: const Color(0xFF475569),
            ),
            child: Slider(
              value: _sliderMilliamps.toDouble(),
              min: ActuatorCurrent.minMilliamps.toDouble(),
              max: ActuatorCurrent.maxMilliamps.toDouble(),
              divisions: ActuatorCurrent.divisions,
              label: '$_sliderMilliamps mA',
              onChanged: enabled
                  ? (value) => setState(
                      () => _sliderMilliamps = ActuatorCurrent.clamp(value),
                    )
                  : null,
              onChangeEnd: enabled
                  ? (value) => _sendCurrentCommand(value.round())
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${ActuatorCurrent.minMilliamps} mA',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              Text(
                '${ActuatorCurrent.maxMilliamps} mA',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(GaitMode mode) {
    final cfg = _modeConfig[mode]!;
    final isActive = _activeMode == mode;
    final isPending = _pendingMode == mode;
    final enabled = _isConnected && !_isCommandPending;

    return GestureDetector(
      onTap: enabled ? () => _handleModeSelect(mode) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive ? cfg.color : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive || isPending
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
          // The card waiting for its feedback stays lit while the others dim.
          opacity: enabled || isPending ? 1.0 : 0.35,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isPending)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cfg.color,
                    ),
                  )
                else
                  Icon(
                    cfg.icon,
                    size: 28,
                    color: isActive ? Colors.white : cfg.color,
                  ),
                const SizedBox(height: 6),
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
    _gaitFeedbackTimer?.cancel();
    _currentFeedbackTimer?.cancel();
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPowerSection(),
                  _buildCurrentSection(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, top: 2),
                    child: Text(
                      _pendingMode != null
                          ? 'Switching to ${_pendingMode!.label}...'
                          : _activeMode != null
                          ? 'Active: ${_activeMode!.label}'
                          : 'Select a gait mode',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  // The cards fill the height left below the label, so the
                  // three rows end exactly at the bottom of the screen and
                  // nothing scrolls. Below [minCellHeight] - a screen too
                  // short for that - the grid scrolls rather than squashing
                  // the cards.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const columns = 3;
                        const spacing = 10.0;
                        const minCellHeight = 86.0;

                        final rows = (GaitMode.values.length / columns).ceil();
                        final gaps = spacing * (rows - 1);
                        final cellWidth =
                            (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                        final cellHeight =
                            ((constraints.maxHeight - gaps) / rows).clamp(
                              minCellHeight,
                              double.infinity,
                            );

                        return GridView.count(
                          crossAxisCount: columns,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: cellWidth / cellHeight,
                          padding: EdgeInsets.zero,
                          children: GaitMode.values
                              .map(_buildModeCard)
                              .toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!_isConnected && !_isConnecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
