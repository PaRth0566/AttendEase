class DbUtils {
  /// Sanitizes a Firestore row for safe SQLite insertion.
  /// Enforces types and basic constraints.
  static Map<String, dynamic> sanitizeRow(Map<String, dynamic> row) {
    final sanitized = <String, dynamic>{};
    for (final entry in row.entries) {
      final key = entry.key;
      var value = entry.value;

      // Handle generic numeric types (Firestore often returns int as double or vice versa)
      if (value is num) {
        if (key == 'required_percent') {
          value = value.toDouble();
        } else {
          value = value.toInt();
        }
      }

      // Enforce basic string constraints
      if (value is String) {
        if (key == 'status') {
          // Normalize to canonical upper-case form so downstream `status == 'P'`
          // comparisons stay consistent; fall back to 'NU' for unknown values.
          final normalized = value.toUpperCase();
          value = ['P', 'A', 'NU', 'NC'].contains(normalized)
              ? normalized
              : 'NU';
        }
        // Limit abnormally long strings
        if (value.length > 255) {
          value = value.substring(0, 255);
        }
      }

      sanitized[key] = value;
    }
    return sanitized;
  }
}
