class MigrationCliException implements Exception {
  final String message;
  final int exitCode;

  MigrationCliException(this.message, this.exitCode);

  @override
  String toString() => message;
}
