import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/mqtt_config.dart';
import '../models/sensor_metadata.dart';
import '../services/mqtt_service.dart';

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key, required this.isActive});

  final bool isActive;

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> with WidgetsBindingObserver {
  static const int _windowSize = 1000;

  static const Duration _renderPeriod = Duration(milliseconds: 100);

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

  List<String> _sensorKeys = [];

  final Map<String, List<FlSpot>> _series = {};

  final Map<String, double> _current = {};

  final List<double> _times = [];

  bool _dirty = false;

  bool _isConnected = false;

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
    } catch (_) {}
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
    _appResumed = state == AppLifecycleState.resumed;
    _syncRendering();
  }

  /// Parses a payload and appends its samples to the per-sensor windows.
  void _onPayload(String payload) {
    final samples = _parseSamples(payload);
    if (samples.isEmpty) return;
    _ingest(samples);
  }

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
      final t = _asDouble(sample[SensorMetadata.timeKey]);
      if (t == null) continue;

      if (_times.isNotEmpty && t < _times.last) {
        _clear();
      }

      if (_sensorKeys.isEmpty) {
        _sensorKeys = sample.keys.where((key) => key != SensorMetadata.timeKey).toList();
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

  void _syncRendering() {
    if (widget.isActive && _appResumed) {
      _renderTimer ??= Timer.periodic(_renderPeriod, (_) => _flush());
    } else {
      _renderTimer?.cancel();
      _renderTimer = null;
    }
  }

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
        title: const Text('Sensors', style: TextStyle(fontWeight: FontWeight.w600)),
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
    final statusColor = _isConnected ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            MqttConfig.validatedLogsTopic,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF94A3B8)),
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
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
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
                  style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          RepaintBoundary(child: SizedBox(height: 140, child: _buildChart(index))),
        ],
      ),
    );
  }

  Widget _buildChart(int index) {
    final key = _sensorKeys[index];
    final color = _colorFor(index);
    final spots = _series[key]!;
    final sensor = SensorMetadata.forKey(key);

    if (spots.length < 2 || _times.length < 2 || _times.last <= _times.first) {
      return const Center(
        child: Text('Waiting for data…', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
      );
    }

    final (minY, maxY) = _yRange(spots);
    final span = maxY - minY;

    final minX = _times.first;
    final maxX = _times.last;
    final timeInterval = _niceInterval(maxX - minX);

    return LineChart(
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
          getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFF334155), strokeWidth: 1),
          getDrawingVerticalLine: (_) => const FlLine(color: Color(0xFF334155), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: timeInterval,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _formatTime(value, timeInterval),
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
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
                  child: Text(_formatTick(value), style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            isStepLineChart: sensor.discrete,
            lineChartStepData: const LineChartStepData(stepDirection: LineChartStepData.stepDirectionForward),
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }

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

  double _niceInterval(double span) {
    final raw = span / 4;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
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

  String _formatTime(double seconds, double interval) {
    final decimals = interval >= 1
        ? 0
        : interval >= 0.1
        ? 1
        : 2;
    return '${seconds.toStringAsFixed(decimals)}s';
  }

  String _formatTick(double value) {
    return value.abs() >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }
}
