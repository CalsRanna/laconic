/// Represents an exception thrown by Laconic.
class LaconicException implements Exception {
  /// The error message.
  final String message;

  /// Creates a new exception with the given message.
  LaconicException(this.message);

  @override
  String toString() {
    return 'LaconicException: $message';
  }
}
