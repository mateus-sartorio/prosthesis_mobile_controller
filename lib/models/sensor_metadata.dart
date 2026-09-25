class SensorMetadata {
  final String label;
  final String? unit;

  const SensorMetadata(this.label, {this.unit});

  static const Map<String, SensorMetadata> _known = {
    'pJ': SensorMetadata('Knee Position', unit: 'cm'),
    'tJ': SensorMetadata('Knee Angle', unit: 'deg'),
    'cJ': SensorMetadata('Knee Current', unit: 'mA'),
    'cJl': SensorMetadata('Knee Current Limited', unit: 'mA'),
    'pP': SensorMetadata('Foot Position', unit: 'cm'),
    'tP': SensorMetadata('Foot Angle', unit: 'deg'),
    'cP': SensorMetadata('Foot Current', unit: 'mA'),
    'cPl': SensorMetadata('Foot Current Limited', unit: 'mA'),
  };

  static final Map<String, SensorMetadata> _byLowerKey = {
    for (final entry in _known.entries) entry.key.toLowerCase(): entry.value,
  };

  static SensorMetadata forKey(String key) {
    return _known[key] ?? _byLowerKey[key.toLowerCase()] ?? SensorMetadata(key);
  }
}
