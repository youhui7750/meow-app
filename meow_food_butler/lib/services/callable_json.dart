/// Cloud Functions decode nested JSON as `Map<Object?, Object?>` / `List<Object?>`,
/// but the model `fromMap` factories cast to `Map<String, dynamic>` /
/// `List<dynamic>`. Deep-normalize a callable payload so those casts succeed.
Map<String, dynamic> normalizeCallableMap(Object? value) {
  final normalized = _normalize(value);
  if (normalized is Map<String, dynamic>) return normalized;
  return <String, dynamic>{};
}

dynamic _normalize(Object? value) {
  if (value is Map) {
    return value.map(
      (key, val) => MapEntry(key.toString(), _normalize(val)),
    );
  }
  if (value is List) {
    return value.map(_normalize).toList();
  }
  return value;
}
