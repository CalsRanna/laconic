/// Represents an exception thrown by Laconic.
class LaconicException implements Exception {
  /// The error message.
  ///
  /// When wrapping a driver-level error, the full message of the original
  /// exception (e.g. `MysqlServerException [1146]: ...`) is embedded here,
  /// so there is no separate cause field.
  final String message;

  /// The driver that produced the error (e.g. `mysql`, `postgres`,
  /// `sqlite`).
  ///
  /// Opaque to the core: laconic does not interpret it, consumers use it to
  /// scope driver-specific [code] values. Filled by drivers when wrapping a
  /// driver-level error; null when the exception was thrown by laconic
  /// itself rather than wrapped from a driver error.
  final String? driver;

  /// Driver-specific error code, opaque to the core.
  ///
  /// Raw format of the originating driver: MySQL server error code
  /// (e.g. `1062` for a duplicate entry), PostgreSQL SQLSTATE
  /// (e.g. `23505`), or SQLite extended result code (e.g. `2067` for
  /// UNIQUE constraint). Values are not comparable across drivers — always
  /// check [driver] first. Null when the driver reported no code or the
  /// error is not a driver-level error.
  final String? code;

  /// Creates a new exception with the given message.
  LaconicException(this.message, {this.driver, this.code});

  @override
  String toString() => 'LaconicException: $message';
}
