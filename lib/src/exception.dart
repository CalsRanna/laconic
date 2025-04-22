class LaconicException implements Exception {
  final String message;

  LaconicException(this.message);

  @override
  String toString() {
    return 'LaconicException: $message';
  }
}
