/// Represents an exception thrown by Laconic.
class LaconicException implements Exception {
  /// The error message.
  final String message;

  /// The original exception that caused this error.
  final Object? cause;

  /// The stack trace from the original exception.
  final StackTrace? stackTrace;

  /// Creates a new exception with the given message.
  LaconicException(this.message, {this.cause, this.stackTrace});

  @override
  String toString() {
    final buffer = StringBuffer('LaconicException: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}
