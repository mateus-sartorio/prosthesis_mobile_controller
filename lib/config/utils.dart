String readString(
  Map<String, dynamic> data,
  String key, {
  required String fallback,
}) {
  final value = data[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return fallback;
}

String? readNullableString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

int readInt(Map<String, dynamic> data, String key, {required int fallback}) {
  final value = data[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}
