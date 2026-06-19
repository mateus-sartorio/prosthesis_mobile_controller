/// Display metadata for a sensor channel: a human-readable [label] and an
/// optional [unit] (e.g. `mA`). Looked up by the raw JSON key carried in the
/// parsed-logs payload via [SensorMetadata.forKey].
class SensorMetadata {
  final String label;
  final String? unit;

  const SensorMetadata(this.label, {this.unit});

  /// Known sensors keyed by their raw payload key.
  ///   * `cX`  — current, `cXl` limited, `cXp` PWM (all in mA)
  ///   * `pX`  — position (unitless)
  static const Map<String, SensorMetadata> _known = {
    'cJ': SensorMetadata('Current J', unit: 'mA'),
    'cJl': SensorMetadata('Current J Limited', unit: 'mA'),
    'cJp': SensorMetadata('Current J PWM', unit: 'mA'),
    'cP': SensorMetadata('Current P', unit: 'mA'),
    'cPl': SensorMetadata('Current P Limited', unit: 'mA'),
    'cPp': SensorMetadata('Current P PWM', unit: 'mA'),
    'pJ': SensorMetadata('Position J'),
    'pP': SensorMetadata('Position P'),
  };

  /// Case-insensitive index over [_known], built once on first use.
  static final Map<String, SensorMetadata> _byLowerKey = {
    for (final entry in _known.entries) entry.key.toLowerCase(): entry.value,
  };

  /// Metadata for [key]. Falls back to the raw key with no unit for sensors
  /// that aren't in the table, so an unrecognized channel still renders.
  static SensorMetadata forKey(String key) {
    return _known[key] ?? _byLowerKey[key.toLowerCase()] ?? SensorMetadata(key);
  }
}
