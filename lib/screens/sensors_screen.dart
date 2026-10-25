import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/mqtt_config.dart';
import '../models/sensor_metadata.dart';
import '../services/mqtt_service.dart';

/// Live plot of the prosthesis' sensors, fed from the validated-logs MQTT topic
/// ([MqttConfig.validatedLogsTopic]). Every payload carries a batch of samples;
/// each JSON key of a sample becomes one sensor channel, except the
/// prosthesis' clock ([SensorMetadata.timeKey]), which places the sample on
/// the time axis every chart shares. Samples are kept in a sliding window so
/// memory stays bounded.
///
/// Two payload shapes are accepted (see [_parseSamples]):
///   * an object `{"value": [ {..}, {..} ]}`, or
///   * a bare array `[ {..}, {..} ]`.
///
/// Data ingestion runs whenever payloads arrive, but rebuilds are throttled by a
/// single [Timer] (~10 Hz) and gated on tab visibility + app lifecycle so we
/// don't relayout off-screen charts. Chart animations are disabled to keep the
/// constant stream from looking like jitter.
class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key, required this.isActive});

  /// Whether this tab is the one currently selected in the bottom nav. The
  /// screen lives in an [IndexedStack] and so is never disposed while the app
  /// runs; rebuilds are gated on this flag so the render timer doesn't keep
  /// relaying out off-screen charts for a tab the user can't see. Incoming MQTT
  /// data is still buffered while hidden so the plot is current on return.
  final bool isActive;

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen>
    with WidgetsBindingObserver {
  /// Maximum number of samples retained per sensor (the sliding window).
  static const int _windowSize = 1000;

  /// How often buffered data is flushed to the UI — ~10 rebuilds per second,
  /// independent of how fast payloads actually arrive.
  static const Duration _renderPeriod = Duration(milliseconds: 100);

  /// Plot colors assigned to sensors by discovery order (cycled if there are
  /// more sensors than colors).
  static const List<Color> _palette = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFDB2777),
    Color(0xFFD97706),
    Color(0xFF0891B2),
    Color(0xFF65A30D),
    Color(0xFFEA580C),
    Color(0xFF6D28D9),
    Color(0xFFE11D48),
  ];

  late final MqttService _mqttService;
  StreamSubscription<String>? _logsSub;
  StreamSubscription<bool>? _statusSub;

  /// Channels to plot, in stable discovery order (captured from the first
  /// sample of a run). The time key is not one of them.
  List<String> _sensorKeys = [];

  /// Sliding window of samples per channel. The x coordinate is the
  /// prosthesis' clock, the same for every channel, so the charts line up.
  final Map<String, List<FlSpot>> _series = {};

  /// Latest value per channel (mirrors the last spot's y; kept for the readout).
  final Map<String, double> _current = {};

  /// Prosthesis time of each retained sample, oldest first. It bounds the
  /// window every chart spans, from its first entry to its last.
  final List<double> _times = [];

  /// Set when new samples have been buffered since the last UI flush.
  bool _dirty = false;

  bool _isConnected = false;

  /// Whether the app is in the foreground. Rebuilds only run when the tab is
  /// both selected ([SensorsScreen.isActive]) and the app is resumed.
  bool _appResumed = true;

  Timer? _renderTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mqttService = MqttService(subscribeToValidatedLogs: true);
    _statusSub = _mqttService.connectionStatusStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });
    _logsSub = _mqttService.validatedLogsStream.listen(_onPayload);
    _syncRendering();
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _mqttService.connect();
    } catch (_) {
      // Failures surface via the connection status stream; the service retries
      // with backoff on its own.
    }
  }

  @override
  void didUpdateWidget(SensorsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The tab was selected or deselected — start/stop the render timer.
    if (widget.isActive != oldWidget.isActive) {
      _syncRendering();
    }
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    _logsSub?.cancel();
    _statusSub?.cancel();
    _mqttService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't relayout charts while backgrounded.
    _appResumed = state == AppLifecycleState.resumed;
    _syncRendering();
  }

  /// Parses a payload and appends its samples to the per-sensor windows.
  void _onPayload(String payload) {
    final samples = _parseSamples(payload);
    if (samples.isEmpty) return;
    _ingest(samples);
  }

  /// Accepts both `{"value": [ ... ]}` and a bare `[ ... ]`, returning the list
  /// of sample objects (each a `{key: value}` map). Returns empty on anything
  /// it can't decode so a malformed payload is simply dropped.
  List<Map<String, dynamic>> _parseSamples(String payload) {
    dynamic decoded;
    try {
      decoded = json.decode(payload);
    } catch (_) {
      return const [];
    }

    List<dynamic>? rawList;
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['value'] is List) {
      rawList = decoded['value'] as List<dynamic>;
    }
    if (rawList == null) return const [];

    return rawList.whereType<Map<String, dynamic>>().toList();
  }

  void _ingest(List<Map<String, dynamic>> samples) {
    for (final sample in samples) {
      // Without its time a sample has no place on the shared axis.
      final t = _asDouble(sample[SensorMetadata.timeKey]);
      if (t == null) continue;

      // The clock starts over from zero whenever the control program is
      // restarted (power on, gait or current change), so a step back in time
      // is a new run, whose samples don't belong on the old run's axis.
      if (_times.isNotEmpty && t < _times.last) {
        _clear();
      }

      // Establish the channel set (and its order) from the run's first sample.
      if (_sensorKeys.isEmpty) {
        _sensorKeys = sample.keys
            .where((key) => key != SensorMetadata.timeKey)
            .toList();
        for (final key in _sensorKeys) {
          _series[key] = <FlSpot>[];
        }
      }

      for (final key in _sensorKeys) {
        final value = _asDouble(sample[key]);
        if (value == null) continue;
        _current[key] = value;
        _series[key]!.add(FlSpot(t, value));
      }
      _times.add(t);
    }

    // Trim the window once per batch (cheaper than removing per sample), then
    // drop from every channel what it holds from before the window.
    if (_times.length > _windowSize) {
      _times.removeRange(0, _times.length - _windowSize);
    }
    if (_times.isNotEmpty) {
      final start = _times.first;
      for (final spots in _series.values) {
        final keep = spots.indexWhere((spot) => spot.x >= start);
        spots.removeRange(0, keep == -1 ? spots.length : keep);
      }
    }

    _dirty = true;
  }

  /// Forgets the current run, channel set included, so the next sample starts
  /// a fresh one.
  void _clear() {
    _sensorKeys = [];
    _series.clear();
    _current.clear();
    _times.clear();
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Starts or stops the render timer so rebuilds happen only while this tab is
  /// visible and the app is foregrounded. Safe to call repeatedly.
  void _syncRendering() {
    if (widget.isActive && _appResumed) {
      _renderTimer ??= Timer.periodic(_renderPeriod, (_) => _flush());
    } else {
      _renderTimer?.cancel();
      _renderTimer = null;
    }
  }

  /// Pushes buffered samples to the UI, but only if something changed.
  void _flush() {
    if (!_dirty) return;
    _dirty = false;
    if (mounted) setState(() {});
  }

  Color _colorFor(int index) => _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Sensors',
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
          _buildStatusBar(),
          Expanded(
            child: _sensorKeys.isEmpty
                ? _buildWaiting()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sensorKeys.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) => _buildSensorCard(index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final statusColor = _isConnected
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);

    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              color: statusColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            MqttConfig.validatedLogsTopic,
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

  Widget _buildWaiting() {
    return Center(
      child: Text(
        _isConnected ? 'Waiting for sensor data…' : 'Connecting…',
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
      ),
    );
  }

  Widget _buildSensorCard(int index) {
    final key = _sensorKeys[index];
    final color = _colorFor(index);
    final value = _current[key];
    final meta = SensorMetadata.forKey(key);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  meta.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value == null ? '--' : meta.format(value),
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (meta.unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  meta.unit!,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Isolate the chart's per-tick repaint into its own layer so it
          // doesn't re-rasterize the card chrome and the live value readout
          // above (ListView already wraps each card, so cards are isolated
          // from each other and the scaffold).
          RepaintBoundary(
            child: SizedBox(height: 140, child: _buildChart(index)),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(int index) {
    final key = _sensorKeys[index];
    final color = _colorFor(index);
    final spots = _series[key]!;
    final sensor = SensorMetadata.forKey(key);

    // Until two samples exist, at two different times, there's nothing to draw
    // a line between.
    if (spots.length < 2 || _times.length < 2 || _times.last <= _times.first) {
      return const Center(
        child: Text(
          'Waiting for data…',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
      );
    }

    // Each sensor has its own scale (the keys span wildly different ranges), so
    // the Y axis auto-fits the visible window rather than using a fixed range.
    final (minY, maxY) = _yRange(spots);
    final span = maxY - minY;

    // Every chart spans the same window of the prosthesis' clock, so a given
    // moment sits at the same horizontal position on all of them.
    final minX = _times.first;
    final maxX = _times.last;
    final timeInterval = _niceInterval(maxX - minX);

    return LineChart(
      // Disable the implicit data-change animation: with new data every ~100 ms
      // it would never settle and would look like jitter.
      duration: Duration.zero,
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          show: true,
          verticalInterval: timeInterval,
          horizontalInterval: span / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFF334155), strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: Color(0xFF334155), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: timeInterval,
              getTitlesWidget: (value, meta) {
                // fl_chart also labels the window's edges, which rarely fall
                // on a round time and would crowd the neighbouring tick.
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _formatTime(value, timeInterval),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: span / 2,
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    _formatTick(value),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            // A state holds until the next sample changes it.
            isStepLineChart: sensor.discrete,
            lineChartStepData: const LineChartStepData(
              stepDirection: LineChartStepData.stepDirectionForward,
            ),
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  /// Min/max of the visible window, padded by 10% so the trace doesn't touch
  /// the chart edges. Flat series get a small symmetric range so a line is
  /// still drawn.
  (double, double) _yRange(List<FlSpot> spots) {
    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final spot in spots) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }
    if (minY == maxY) {
      final pad = minY.abs() < 1 ? 1.0 : minY.abs() * 0.1;
      return (minY - pad, maxY + pad);
    }
    final pad = (maxY - minY) * 0.1;
    return (minY - pad, maxY + pad);
  }

  /// A round step for the time axis giving about four ticks across [span]
  /// seconds: 1, 2 or 5 times a power of ten. Round steps keep the ticks on
  /// round times, so they scroll with the data instead of jumping around.
  double _niceInterval(double span) {
    final raw = span / 4;
    final magnitude = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final normalized = raw / magnitude;
    final step = normalized < 1.5
        ? 1.0
        : normalized < 3
        ? 2.0
        : normalized < 7
        ? 5.0
        : 10.0;
    return step * magnitude;
  }

  /// Bottom-axis label: the prosthesis' time in seconds, with as many decimals
  /// as the tick [interval] needs to tell neighbouring ticks apart.
  String _formatTime(double seconds, double interval) {
    final decimals = interval >= 1
        ? 0
        : interval >= 0.1
        ? 1
        : 2;
    return '${seconds.toStringAsFixed(decimals)}s';
  }

  /// Axis labels: drop the decimals once values get large enough that they'd
  /// just be noise, keep one decimal for small-range sensors.
  String _formatTick(double value) {
    return value.abs() >= 10
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}
