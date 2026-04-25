import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

void main() {
  late Directory dataDir;
  late Directory webDir;
  late _ServerHarness server;

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('pathplanner-data-');
    webDir = await Directory.systemTemp.createTemp('pathplanner-web-');
    server = await _ServerHarness.start(dataDir: dataDir, webDir: webDir);
  });

  tearDown(() async {
    await server.stop();
    if (dataDir.existsSync()) {
      await dataDir.delete(recursive: true);
    }
    if (webDir.existsSync()) {
      await webDir.delete(recursive: true);
    }
  });

  test('malformed JSON returns a clean bad request', () async {
    final response = await http.post(
      server.uri('/api/teams'),
      headers: {'Content-Type': 'application/json'},
      body: '{',
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(jsonDecode(response.body), containsPair('error', contains('JSON')));
  });

  test('delete removes an auto and CORS allows DELETE', () async {
    final createResponse = await http.post(
      server.uri('/api/teams/1477/autos'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'Test Auto',
        'fieldId': 'rebuilt',
        'points': const [],
      }),
    );
    expect(createResponse.statusCode, HttpStatus.created);

    final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final auto = created['auto'] as Map<String, dynamic>;
    final storageId = auto['storageId'] as String;
    final savedFile = File(
      p.join(dataDir.path, 'teams', '1477', '$storageId.json'),
    );
    expect(savedFile.existsSync(), isTrue);

    final optionsResponse = await http.Request(
      'OPTIONS',
      server.uri('/api/teams/1477/autos/$storageId'),
    ).send();
    expect(optionsResponse.statusCode, HttpStatus.noContent);
    expect(
      optionsResponse.headers['access-control-allow-methods'],
      contains('DELETE'),
    );

    final deleteResponse = await http.delete(
      server.uri('/api/teams/1477/autos/$storageId'),
    );
    expect(deleteResponse.statusCode, HttpStatus.ok);
    expect(savedFile.existsSync(), isFalse);
  });
}

class _ServerHarness {
  final Process process;
  final int port;
  final StreamSubscription<String> _stdoutSub;
  final StreamSubscription<String> _stderrSub;
  final StringBuffer _stderrBuffer;

  const _ServerHarness({
    required this.process,
    required this.port,
    required StreamSubscription<String> stdoutSub,
    required StreamSubscription<String> stderrSub,
    required StringBuffer stderrBuffer,
  })  : _stdoutSub = stdoutSub,
        _stderrSub = stderrSub,
        _stderrBuffer = stderrBuffer;

  static Future<_ServerHarness> start({
    required Directory dataDir,
    required Directory webDir,
  }) async {
    final port = await _freePort();
    final process = await Process.start(
      'dart',
      [
        'run',
        'bin/webui_server.dart',
        '--port=$port',
        '--data-dir=${dataDir.path}',
        '--web-dir=${webDir.path}',
      ],
      workingDirectory: Directory.current.path,
    );

    final ready = Completer<void>();
    late final StreamSubscription<String> stdoutSub;
    stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.contains('PathPlanner scouting web server running')) {
        ready.complete();
      }
    });
    final stderrBuffer = StringBuffer();
    final stderrSub = process.stderr.transform(utf8.decoder).listen(
          stderrBuffer.write,
        );

    try {
      await ready.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw StateError(
            'Timed out waiting for server. stderr: $stderrBuffer',
          );
        },
      );
    } catch (_) {
      process.kill();
      rethrow;
    }

    return _ServerHarness(
      process: process,
      port: port,
      stdoutSub: stdoutSub,
      stderrSub: stderrSub,
      stderrBuffer: stderrBuffer,
    );
  }

  Uri uri(String path) => Uri.parse('http://127.0.0.1:$port$path');

  Future<void> stop() async {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    if (_stderrBuffer.isNotEmpty) {
      // Keep stderr available in failing test output without logging on success.
      stderr.write(_stderrBuffer.toString());
    }
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}
