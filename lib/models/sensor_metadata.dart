class SensorMetadata {
  final String label;
  final String? unit;

  final bool discrete;

  const SensorMetadata(this.label, {this.unit, this.discrete = false});

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

  String format(double value) {
    final text = value.toStringAsFixed(2);
    return discrete ? text.replaceFirst(_trailingZeros, '') : text;
  }
}
