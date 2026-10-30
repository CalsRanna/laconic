import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../exception.dart';

/// Optional native schema export/import support implemented by a driver.
abstract interface class SchemaStateDriver {
  /// Identifies the native SQL format used by the dump.
  String get schemaDialect;

  /// Exports schema only to [path], without table data.
  Future<void> dumpSchema(
    String path, {
    String? schema,
    SchemaProcessRunner? runner,
  });

  /// Loads trusted SQL through the native client into its original schema names.
  ///
  /// [schema] identifies the history namespace; it does not rewrite SQL names.
  Future<void> loadSchema(
    String path, {
    String? schema,
    SchemaProcessRunner? runner,
  });
}

/// Runs native schema clients without a shell and streams SQL through files.
///
/// Override [run] to supply a containerized client or a custom executable path.
/// Credentials are supplied in [environment], never shell command strings.
class SchemaProcessRunner {
  /// Creates a native process runner.
  const SchemaProcessRunner();

  /// Executes a native client, optionally piping SQL input or output.
  Future<void> run(
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? inputPath,
    String? outputPath,
  }) async {
    Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        environment: environment,
      );
    } on ProcessException catch (error) {
      throw LaconicException(
        'Cannot start schema client $executable: ${error.message}',
      );
    }
    final errors = StringBuffer();
    final signals = <StreamSubscription<ProcessSignal>>[
      ProcessSignal.sigint.watch().listen(process.kill),
      if (!Platform.isWindows)
        ProcessSignal.sigterm.watch().listen(process.kill),
    ];
    Object? ioError;
    try {
      await Future.wait<void>([
        outputPath == null
            ? process.stdout.drain<void>()
            : process.stdout.pipe(File(outputPath).openWrite()),
        process.stderr.transform(utf8.decoder).forEach((text) {
          if (errors.length < 8192) {
            errors.write(
              text.substring(0, text.length.clamp(0, 8192 - errors.length)),
            );
          }
        }),
        () async {
          try {
            if (inputPath != null) {
              await process.stdin.addStream(File(inputPath).openRead());
            }
          } finally {
            await process.stdin.close();
          }
        }(),
      ]).catchError((Object error) {
        ioError = error;
        return <void>[];
      });
      final code = await process.exitCode;
      if (code != 0 || ioError != null) {
        var message = errors.toString().trim();
        if (ioError != null) message = '$message\n$ioError'.trim();
        for (final entry in environment.entries) {
          if ((entry.key.contains('PASSWORD') || entry.key.endsWith('PWD')) &&
              entry.value.isNotEmpty) {
            message = message.replaceAll(entry.value, '<redacted>');
          }
        }
        throw LaconicException(
          'Schema client $executable failed (exit $code)${message.isEmpty ? '' : ': $message'}',
        );
      }
    } finally {
      for (final signal in signals) {
        await signal.cancel();
      }
    }
  }
}
