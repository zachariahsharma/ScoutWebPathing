import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pathplanner/webui/export/observed_auto_export.dart';

Future<void> main(List<String> args) async {
  final config = _ServerConfig.fromArgs(args);
  final server = await HttpServer.bind(config.host, config.port);

  stdout.writeln(
    'PathPlanner scouting web server running on http://${config.host}:${config.port}',
  );
  stdout.writeln('Data directory: ${config.dataDir.path}');
  if (config.webDir.existsSync()) {
    stdout.writeln('Serving static files from ${config.webDir.path}');
  } else {
    stdout.writeln('No web build found at ${config.webDir.path}');
  }

  await for (final request in server) {
    unawaited(_handleRequest(request, config));
  }
}

class _ServerConfig {
  final String host;
  final int port;
  final Directory dataDir;
  final Directory webDir;

  const _ServerConfig({
    required this.host,
    required this.port,
    required this.dataDir,
    required this.webDir,
  });

  factory _ServerConfig.fromArgs(List<String> args) {
    String host = '127.0.0.1';
    int port = 8080;
    String dataDir = 'webui_data';
    String webDir = 'build/web';

    for (final arg in args) {
      if (arg.startsWith('--host=')) {
        host = arg.substring('--host='.length);
      } else if (arg.startsWith('--port=')) {
        port = int.tryParse(arg.substring('--port='.length)) ?? port;
      } else if (arg.startsWith('--data-dir=')) {
        dataDir = arg.substring('--data-dir='.length);
      } else if (arg.startsWith('--web-dir=')) {
        webDir = arg.substring('--web-dir='.length);
      }
    }

    final resolvedDataDir = Directory(dataDir)..createSync(recursive: true);
    final teamsDir = Directory(p.join(resolvedDataDir.path, 'teams'))
      ..createSync(recursive: true);

    return _ServerConfig(
      host: host,
      port: port,
      dataDir: teamsDir,
      webDir: Directory(webDir),
    );
  }
}

Future<void> _handleRequest(HttpRequest request, _ServerConfig config) async {
  _setCorsHeaders(request.response);

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  try {
    final segments = request.uri.pathSegments;
    if (segments.isNotEmpty && segments.first == 'api') {
      await _handleApiRequest(request, config, segments.skip(1).toList());
      return;
    }

    await _serveStatic(request, config.webDir);
  } on _HttpException catch (error) {
    request.response.statusCode = error.statusCode;
    await _writeJson(request.response, {'error': error.message});
  } catch (error) {
    request.response.statusCode = HttpStatus.internalServerError;
    await _writeJson(request.response, {'error': error.toString()});
  }
}

Future<void> _handleApiRequest(
  HttpRequest request,
  _ServerConfig config,
  List<String> segments,
) async {
  if (segments.isEmpty) {
    await _writeJson(request.response, {'ok': true});
    return;
  }

  if (segments.length == 1 && segments.first == 'teams') {
    if (request.method == 'GET') {
      final teams = config.dataDir
          .listSync()
          .whereType<Directory>()
          .map((dir) => p.basename(dir.path))
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      await _writeJson(request.response, {'teams': teams});
      return;
    }

    if (request.method == 'POST') {
      final body = await _readJson(request);
      final teamName = _validatedName(body['name'] as String?, 'team');
      Directory(
        p.join(config.dataDir.path, teamName),
      ).createSync(recursive: true);
      await _writeJson(request.response, {'team': teamName});
      return;
    }
  }

  if (segments.length == 3 &&
      segments.first == 'teams' &&
      segments[2] == 'export.pdf' &&
      request.method == 'GET') {
    final team = _validatedName(segments[1], 'team');
    final teamDir = Directory(p.join(config.dataDir.path, team));
    teamDir.createSync(recursive: true);
    final autos = <Map<String, dynamic>>[];
    for (final file in teamDir.listSync().whereType<File>()) {
      if (p.extension(file.path) != '.json') {
        continue;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      autos.add(json);
    }

    final pdfBytes = await ObservedAutoExport.renderTeamPdf(team, autos);
    request.response.headers.contentType = ContentType('application', 'pdf');
    request.response.headers.set(
      'Content-Disposition',
      'attachment; filename="${_slugify(team)}-autos.pdf"',
    );
    request.response.add(pdfBytes);
    await request.response.close();
    return;
  }

  if (segments.length >= 3 &&
      segments.first == 'teams' &&
      segments[2] == 'autos') {
    final team = _validatedName(segments[1], 'team');
    final teamDir = Directory(p.join(config.dataDir.path, team));
    teamDir.createSync(recursive: true);

    if (segments.length == 3 && request.method == 'GET') {
      final autos = teamDir
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.json')
          .map((file) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return {
          'id': p.basenameWithoutExtension(file.path),
          'name': json['name'] ?? p.basenameWithoutExtension(file.path),
          'updatedAt': json['updatedAt'] ?? '',
          'fieldId': json['fieldId'] ?? 'rebuilt',
          'points': json['points'] ?? const [],
          'waypointTimings': json['waypointTimings'] ?? const [],
          'path': json['path'],
          'canMirror': json['canMirror'] ?? false,
          'mirrorRotations': json['mirrorRotations'] ?? const [],
          'matches': json['matches'] ?? const [],
          'selectedMatchId': json['selectedMatchId'],
        };
      }).toList()
        ..sort(
          (a, b) => (b['updatedAt'] as String).compareTo(
            a['updatedAt'] as String,
          ),
        );
      await _writeJson(request.response, {'autos': autos});
      return;
    }

    if (segments.length == 3 && request.method == 'POST') {
      final auto = await _readJson(request);
      final storageId = _nextStorageId(
        teamDir,
        _slugify((auto['name'] as String?) ?? 'auto'),
      );
      final saved = _normalizedAuto(auto, team: team, storageId: storageId);
      await File(
        p.join(teamDir.path, '$storageId.json'),
      ).writeAsString(_prettyJson(saved));
      request.response.statusCode = HttpStatus.created;
      await _writeJson(request.response, {'auto': saved});
      return;
    }

    if (segments.length >= 4) {
      final storageId = _validatedName(segments[3], 'auto id');
      final file = File(p.join(teamDir.path, '$storageId.json'));

      if (segments.length == 4 && request.method == 'GET') {
        if (!file.existsSync()) {
          throw const _HttpException(HttpStatus.notFound, 'Auto not found.');
        }
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        await _writeJson(request.response, {'auto': json});
        return;
      }

      if (segments.length == 4 && request.method == 'PUT') {
        final auto = await _readJson(request);
        final existingCreatedAt = file.existsSync()
            ? (jsonDecode(await file.readAsString())
                as Map<String, dynamic>)['createdAt'] as String?
            : null;
        final saved = _normalizedAuto(
          auto,
          team: team,
          storageId: storageId,
          createdAt: existingCreatedAt,
        );
        await file.writeAsString(_prettyJson(saved));
        await _writeJson(request.response, {'auto': saved});
        return;
      }

      if (segments.length == 5 &&
          segments[4] == 'export' &&
          request.method == 'GET') {
        if (!file.existsSync()) {
          throw const _HttpException(HttpStatus.notFound, 'Auto not found.');
        }
        request.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.response.headers.set(
          'Content-Disposition',
          'attachment; filename="$storageId.json"',
        );
        await request.response.addStream(file.openRead());
        await request.response.close();
        return;
      }

      if (segments.length == 5 &&
          segments[4] == 'render.jpeg' &&
          request.method == 'GET') {
        if (!file.existsSync()) {
          throw const _HttpException(HttpStatus.notFound, 'Auto not found.');
        }
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final jpegBytes = await ObservedAutoExport.renderJpeg(
          json,
          matchId: request.uri.queryParameters['match'],
        );
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.headers.set(
          'Content-Disposition',
          'attachment; filename="$storageId.jpeg"',
        );
        request.response.add(jpegBytes);
        await request.response.close();
        return;
      }
    }
  }

  throw const _HttpException(HttpStatus.notFound, 'Route not found.');
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

Map<String, dynamic> _normalizedAuto(
  Map<String, dynamic> auto, {
  required String team,
  required String storageId,
  String? createdAt,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    'version': 3,
    'storageId': storageId,
    'team': team,
    'name': (auto['name'] as String?)?.trim().isNotEmpty == true
        ? (auto['name'] as String).trim()
        : 'Untitled Auto',
    'fieldId': auto['fieldId'] ?? 'rebuilt',
    'createdAt': createdAt ?? auto['createdAt'] ?? now,
    'updatedAt': now,
    'points': (auto['points'] as List<dynamic>? ?? const []),
    'waypointTimings': (auto['waypointTimings'] as List<dynamic>? ?? const []),
    'path': auto['path'],
    'canMirror': auto['canMirror'] ?? false,
    'mirrorRotations': (auto['mirrorRotations'] as List<dynamic>? ?? const []),
    'matches': (auto['matches'] as List<dynamic>? ?? const []),
    'selectedMatchId': auto['selectedMatchId'],
  };
}

String _nextStorageId(Directory teamDir, String baseId) {
  var candidate = baseId;
  int suffix = 2;
  while (File(p.join(teamDir.path, '$candidate.json')).existsSync()) {
    candidate = '$baseId-$suffix';
    suffix++;
  }
  return candidate;
}

String _slugify(String input) {
  final normalized = input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return normalized.isEmpty ? 'auto' : normalized;
}

String _validatedName(String? input, String label) {
  final value = input?.trim() ?? '';
  if (value.isEmpty) {
    throw _HttpException(HttpStatus.badRequest, 'Missing $label.');
  }
  if (value.contains('/') ||
      value.contains(r'\') ||
      value == '.' ||
      value == '..') {
    throw _HttpException(HttpStatus.badRequest, 'Invalid $label.');
  }
  return value;
}

Future<void> _serveStatic(HttpRequest request, Directory webDir) async {
  if (!webDir.existsSync()) {
    request.response.statusCode = HttpStatus.notFound;
    await _writeJson(request.response, {
      'error':
          'No built web app found. Run flutter build web --target lib/main_web.dart first.',
    });
    return;
  }

  final rawPath = request.uri.path == '/' ? '/index.html' : request.uri.path;
  final safePath = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
  final normalizedPath = p.normalize(safePath);
  if (normalizedPath.startsWith('..')) {
    throw const _HttpException(HttpStatus.badRequest, 'Invalid static path.');
  }

  final file = File(p.join(webDir.path, normalizedPath));
  final exists = file.existsSync();
  final target = exists ? file : File(p.join(webDir.path, 'index.html'));

  if (!target.existsSync()) {
    request.response.statusCode = HttpStatus.notFound;
    await _writeJson(request.response, {'error': 'Static file not found.'});
    return;
  }

  request.response.headers.contentType = _contentTypeFor(target.path);
  await request.response.addStream(target.openRead());
  await request.response.close();
}

ContentType _contentTypeFor(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.html':
      return ContentType.html;
    case '.js':
      return ContentType('application', 'javascript', charset: 'utf-8');
    case '.css':
      return ContentType('text', 'css', charset: 'utf-8');
    case '.json':
      return ContentType.json;
    case '.png':
      return ContentType('image', 'png');
    case '.jpg':
    case '.jpeg':
      return ContentType('image', 'jpeg');
    case '.svg':
      return ContentType('image', 'svg+xml');
    case '.wasm':
      return ContentType('application', 'wasm');
    default:
      return ContentType.binary;
  }
}

void _setCorsHeaders(HttpResponse response) {
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, PUT, OPTIONS',
  );
  response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
}

Future<void> _writeJson(
  HttpResponse response,
  Map<String, dynamic> body,
) async {
  response.headers.contentType = ContentType.json;
  response.write(_prettyJson(body));
  await response.close();
}

String _prettyJson(Object body) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(body);
}

class _HttpException implements Exception {
  final int statusCode;
  final String message;

  const _HttpException(this.statusCode, this.message);

  @override
  String toString() => message;
}
