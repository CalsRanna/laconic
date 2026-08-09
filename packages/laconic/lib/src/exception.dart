/// Represents an exception thrown by Laconic.
class LaconicException implements Exception {
  /// The error message.
  ///
  /// When wrapping a driver-level error, the full message of the original
  /// exception (e.g. `MysqlServerException [1146]: ...`) is embedded here,
  /// so there is no separate cause field.
  final String message;

  /// Creates a new exception with the given message.
  LaconicException(this.message);

  @override
  String toString() => 'LaconicException: $message';
}
