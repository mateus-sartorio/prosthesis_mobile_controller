import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Live plot of the prothesis' six sensors. Each sensor is a temporal series
/// sampled at ~10 Hz; only the most recent [_windowSize] samples are kept in a
/// sliding window so memory stays bounded. Values are currently synthesized
/// (a bounded random walk) until real sensor telemetry is wired in.
///
/// A single [Timer] drives all six series and triggers one [setState] per tick
/// (so 10 rebuilds/second rather than 60), and chart animations are disabled
/// to keep the stream smooth under the constant data churn.
class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key, required this.isActive});

  /// Whether this tab is the one currently selected in the bottom nav. The
  /// screen lives in an [IndexedStack] and so is never disposed while the app
  /// runs; sampling is gated on this flag so the 10 Hz timer and its rebuilds
  /// don't keep running (rebuilding/laying out off-screen charts) for a tab the
  /// user can't see.
  final bool isActive;

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

/// Static description of a single sensor channel: its label, plot color and the
/// expected value range (used to fix the Y axis so it doesn't jitter as data
/// scrolls past).
class _SensorSpec {
  const _SensorSpec({
    required this.label,
    required this.color,
    required this.min,
    required this.max,
  });

  final String label;
  final Color color;
  final double min;
  final double max;

  double get mid => (min + max) / 2;
}

class _SensorsScreenState extends State<SensorsScreen>
    with WidgetsBindingObserver {
  /// Maximum number of samples retained per sensor (the sliding window).
  static const int _windowSize = 1000;

  /// Time between samples — ~10 updates per second.
  static const Duration _samplePeriod = Duration(milliseconds: 100);

  static const List<_SensorSpec> _specs = [
    _SensorSpec(label: 'Sensor 1', color: Color(0xFF2563EB), min: 0, max: 100),
    _SensorSpec(label: 'Sensor 2', color: Color(0xFF7C3AED), min: -50, max: 50),
    _SensorSpec(label: 'Sensor 3', color: Color(0xFF059669), min: 0, max: 360),
    _SensorSpec(label: 'Sensor 4', color: Color(0xFFDB2777), min: -10, max: 10),
    _SensorSpec(label: 'Sensor 5', color: Color(0xFFD97706), min: 0, max: 200),
    _SensorSpec(label: 'Sensor 6', color: Color(0xFF0891B2), min: -100, max: 100),
  ];

  final Random _rng = Random();

  /// Sliding window of samples per sensor. The x coordinate is a monotonically
  /// increasing sample index so the plot scrolls left as new data arrives.
  late final List<List<FlSpot>> _series;

  /// Latest value per sensor (mirrors the last spot's y; kept for the readout).
  late final List<double> _current;

  /// Global sample counter, used as the x coordinate for every series.
  int _sampleIndex = 0;

  /// Whether the app is in the foreground. Sampling only runs when the tab is
  /// both selected ([SensorsScreen.isActive]) and the app is resumed.
  bool _appResumed = true;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _series = List.generate(_specs.length, (_) => <FlSpot>[]);
    _current = _specs.map((s) => s.mid).toList();
    _syncSampling();
  }

  @override
  void didUpdateWidget(SensorsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The tab was selected or deselected — start/stop the timer accordingly.
    if (widget.isActive != oldWidget.isActive) {
      _syncSampling();
    }
  }

  @override
  void dispose() {
    _stopSampling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't burn CPU/battery generating samples while backgrounded.
    _appResumed = state == AppLifecycleState.resumed;
    _syncSampling();
  }

  /// Starts or stops the sampling timer so it runs only while this tab is
  /// visible and the app is foregrounded. Safe to call repeatedly — the timer
  /// guard makes starting idempotent.
  void _syncSampling() {
    if (widget.isActive && _appResumed) {
      _startSampling();
    } else {
      _stopSampling();
    }
  }

  void _startSampling() {
    _timer ??= Timer.periodic(_samplePeriod, (_) => _tick());
  }

  void _stopSampling() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    final x = _sampleIndex.toDouble();
    for (var i = 0; i < _specs.length; i++) {
      _current[i] = _nextValue(i);
      final buffer = _series[i];
      buffer.add(FlSpot(x, _current[i]));
      if (buffer.length > _windowSize) {
        buffer.removeAt(0);
      }
    }
    _sampleIndex++;
    if (mounted) setState(() {});
  }

  /// Bounded random walk: nudges the previous value by a small random step and
  /// clamps it to the sensor's range, yielding a signal that looks plausibly
  /// sensor-like rather than pure noise.
  double _nextValue(int i) {
    final spec = _specs[i];
    final span = spec.max - spec.min;
    final step = (_rng.nextDouble() - 0.5) * span * 0.08;
    return (_current[i] + step).clamp(spec.min, spec.max);
  }

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
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _specs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _buildSensorCard(index),
      ),
    );
  }

  Widget _buildSensorCard(int index) {
    final spec = _specs[index];

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
                decoration: BoxDecoration(
                  color: spec.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                spec.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _current[index].toStringAsFixed(2),
                style: TextStyle(
                  color: spec.color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
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
    final spec = _specs[index];
    final spots = _series[index];

    // Until at least two samples exist there's nothing to draw a line between.
    if (spots.length < 2) {
      return const Center(
        child: Text(
          'Waiting for data…',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
      );
    }

    final span = spec.max - spec.min;

    return LineChart(
      // Disable the implicit data-change animation: with new data every 100 ms
      // it would never settle and would look like jitter.
      duration: Duration.zero,
      LineChartData(
        minX: spots.first.x,
        maxX: spots.last.x,
        minY: spec.min,
        maxY: spec.max,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: span / 4,
          getDrawingHorizontalLine: (_) =>
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
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: span / 2,
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value.toStringAsFixed(0),
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
            color: spec.color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: spec.color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}