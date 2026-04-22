import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pathplanner/webui/models/observed_auto.dart';

class WebUiApi {
  WebUiApi({String? baseUrl}) : _baseUrl = _resolveBaseUrl(baseUrl);

  final String _baseUrl;

  static String _resolveBaseUrl(String? override) {
    if (override != null && override.isNotEmpty) {
      return override.replaceAll(RegExp(r'/$'), '');
    }
    const envUrl = String.fromEnvironment('PATHPLANNER_WEBUI_API');
    if (envUrl.isNotEmpty) {
      return envUrl.replaceAll(RegExp(r'/$'), '');
    }
    final base = Uri.base;
    if (base.scheme == 'http' || base.scheme == 'https') {
      return base.origin;
    }
    return 'http://127.0.0.1:8080';
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<List<String>> fetchTeams() async {
    final response = await http.get(_uri('/api/teams'));
    final json = _decode(response);
    final teams = (json['teams'] as List<dynamic>? ?? []).cast<String>();
    return teams;
  }

  Future<void> createTeam(String teamName) async {
    final response = await http.post(
      _uri('/api/teams'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': teamName}),
    );
    _decode(response);
  }

  Future<List<ObservedAutoSummary>> fetchAutos(String team) async {
    final response = await http.get(
      _uri('/api/teams/${Uri.encodeComponent(team)}/autos'),
    );
    final json = _decode(response);
    final autos =
        (json['autos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return autos.map(ObservedAutoSummary.fromJson).toList();
  }

  Future<ObservedAuto> fetchAuto(String team, String storageId) async {
    final response = await http.get(
      _uri(
        '/api/teams/${Uri.encodeComponent(team)}/autos/${Uri.encodeComponent(storageId)}',
      ),
    );
    final json = _decode(response);
    return ObservedAuto.fromJson(json['auto'] as Map<String, dynamic>);
  }

  Future<ObservedAuto> saveAuto(ObservedAuto auto) async {
    final path = auto.storageId.isEmpty
        ? '/api/teams/${Uri.encodeComponent(auto.team)}/autos'
        : '/api/teams/${Uri.encodeComponent(auto.team)}/autos/${Uri.encodeComponent(auto.storageId)}';
    final response = auto.storageId.isEmpty
        ? await http.post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(auto.toJson()),
          )
        : await http.put(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(auto.toJson()),
          );
    final json = _decode(response);
    return ObservedAuto.fromJson(json['auto'] as Map<String, dynamic>);
  }

  Uri exportUri(ObservedAuto auto) {
    return _uri(
      '/api/teams/${Uri.encodeComponent(auto.team)}/autos/${Uri.encodeComponent(auto.storageId)}/export',
    );
  }

  Uri renderAutoJpegUri(ObservedAuto auto, {String? matchId}) {
    final query = <String, String>{};
    if (matchId != null && matchId.isNotEmpty) {
      query['match'] = matchId;
    }
    return _uri(
      '/api/teams/${Uri.encodeComponent(auto.team)}/autos/${Uri.encodeComponent(auto.storageId)}/render.jpeg${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}',
    );
  }

  Uri exportTeamPdfUri(String team) {
    return _uri(
      '/api/teams/${Uri.encodeComponent(team)}/export.pdf',
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty ? '{}' : response.body;
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebUiApiException(decoded['error'] as String? ?? 'Request failed');
    }
    return decoded;
  }
}

class WebUiApiException implements Exception {
  final String message;

  WebUiApiException(this.message);

  @override
  String toString() => message;
}
