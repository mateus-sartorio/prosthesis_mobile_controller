class SensorMetadata {
  final String label;
  final String? unit;

  /// Whether the channel holds a discrete value (a state) rather than a
  /// continuous measurement: it is drawn in steps and read out without
  /// trailing zeros.
  final bool discrete;

  const SensorMetadata(this.label, {this.unit, this.discrete = false});

  /// Key of the prosthesis' clock, in seconds. Not a channel: it places every
  /// sample on the time axis the charts share.
  static const String timeKey = 't';

  static const Map<String, SensorMetadata> _known = {
    's': SensorMetadata('Microstate', discrete: true),
    'pJ': SensorMetadata('Knee Angle', unit: '°'),
    'cJ': SensorMetadata('Knee Current', unit: 'mA'),
    'cJl': SensorMetadata('Knee Current Limited', unit: 'mA'),
    'pP': SensorMetadata('Foot Angle', unit: '°'),
    'cP': SensorMetadata('Foot Current', unit: 'mA'),
    'cPl': SensorMetadata('Foot Current Limited', unit: 'mA'),
  };

  static final Map<String, SensorMetadata> _byLowerKey = {
    for (final entry in _known.entries) entry.key.toLowerCase(): entry.value,
  };

  static SensorMetadata forKey(String key) {
    return _known[key] ?? _byLowerKey[key.toLowerCase()] ?? SensorMetadata(key);
  }

  static final RegExp _trailingZeros = RegExp(r'\.?0+$');

  /// [value] as the readout shows it: two decimals for measurements; for a
  /// discrete channel only the decimals it has, so state 2.5 reads `2.5` and
  /// state 3 reads `3`.
  String format(double value) {
    final text = value.toStringAsFixed(2);
    return discrete ? text.replaceFirst(_trailingZeros, '') : text;
  }
}
