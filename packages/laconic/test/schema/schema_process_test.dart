import 'dart:io';

import 'package:laconic/laconic.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File script;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('laconic_schema_client_');
    script = File(p.join(directory.path, 'client.dart'));
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'native runner streams file input/output without shell interpretation',
    () async {
      await script.writeAsString("""import 'dart:io';
Future<void> main(List<String> args) async {
  stdout.writeln(args.single);
  await stdin.pipe(stdout);
}
""");
      final input = File(p.join(directory.path, 'input.sql'));
      final output = File(p.join(directory.path, 'output.sql'));
      await input.writeAsString('select 1;\n');
      await const SchemaProcessRunner().run(
        Platform.resolvedExecutable,
        [script.path, r'literal $(echo secret) `echo secret`'],
        inputPath: input.path,
        outputPath: output.path,
      );
      expect(
        await output.readAsString(),
        'literal \$(echo secret) `echo secret`\nselect 1;\n',
      );
    },
  );

  test(
    'native client failures are bounded and redact password environment',
    () async {
      await script.writeAsString("""import 'dart:io';
void main() { stderr.writeln(Platform.environment['MYSQL_PWD']); stderr.write('x' * 20000); exitCode = 2; }
""");
      await expectLater(
        const SchemaProcessRunner().run(
          Platform.resolvedExecutable,
          [script.path],
          environment: {'MYSQL_PWD': 'test-client-secret'},
        ),
        throwsA(
          isA<LaconicException>()
              .having((e) => e.toString(), 'redacted', contains('<redacted>'))
              .having(
                (e) => e.toString(),
                'no password',
                isNot(contains('test-client-secret')),
              )
              .having((e) => e.toString().length, 'bounded', lessThan(8500)),
        ),
      );
    },
  );

  test('missing native client reports an actionable failure', () async {
    await expectLater(
      const SchemaProcessRunner().run(
        p.join(directory.path, 'missing-client'),
        [],
      ),
      throwsA(
        isA<LaconicException>().having(
          (e) => e.toString(),
          'message',
          contains('Cannot start schema client'),
        ),
      ),
    );
  });
}
