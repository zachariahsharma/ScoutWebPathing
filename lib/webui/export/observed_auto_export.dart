import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const Object _unchanged = Object();

double _sortTime(double? timeSeconds) {
  return timeSeconds ?? double.infinity;
}

class ObservedAutoExport {
  static const int _infoPanelWidth = 700;

  static Future<Uint8List> renderJpeg(
    Map<String, dynamic> autoJson, {
    String? matchId,
  }) async {
    final view =
        _ResolvedAutoView.fromJson(autoJson, requestedMatchId: matchId);
    final field = _ServerFieldSpec.byId(view.fieldId);
    final fieldImage =
        img.decodeImage(await File(field.assetPath).readAsBytes());
    if (fieldImage == null) {
      throw Exception('Failed to load field image: ${field.assetPath}');
    }

    final viewport = _FieldViewport.forView(field, view);
    final visibleFieldImage = viewport.isFullWidth
        ? fieldImage
        : img.copyCrop(
            fieldImage,
            x: viewport.x,
            y: 0,
            width: viewport.width,
            height: fieldImage.height,
          );

    final canvasWidth = visibleFieldImage.width + _infoPanelWidth;
    final canvasHeight = max(fieldImage.height, 1800);
    final canvas = img.Image(
      width: canvasWidth,
      height: canvasHeight,
      numChannels: 4,
    );

    img.fill(canvas, color: img.ColorRgb8(5, 5, 5));
    img.compositeImage(canvas, visibleFieldImage, dstX: 0, dstY: 0);
    _paintPath(canvas, field, viewport, view);
    _paintInfoPanel(canvas, visibleFieldImage.width, view);

    return Uint8List.fromList(img.encodeJpg(canvas, quality: 92));
  }

  static Future<Uint8List> renderTeamPdf(
    String team,
    List<Map<String, dynamic>> autoJsonList,
  ) async {
    final doc = pw.Document();

    for (final autoJson in autoJsonList) {
      final view = _ResolvedAutoView.fromJson(autoJson);
      final imageBytes = await renderJpeg(autoJson);
      final image = pw.MemoryImage(imageBytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(18),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '$team • ${view.name}',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return Uint8List.fromList(await doc.save());
  }

  static void _paintPath(
    img.Image canvas,
    _ServerFieldSpec field,
    _FieldViewport viewport,
    _ResolvedAutoView view,
  ) {
    final positions = view.sampledPathPositions;
    if (positions.isEmpty) {
      return;
    }

    final gold = img.ColorRgb8(212, 164, 55);
    final glow = img.ColorRgb8(244, 211, 122);
    final black = img.ColorRgb8(8, 8, 8);
    final occupiedTags = <_LabelRect>[];

    for (int i = 0; i < positions.length - 1; i++) {
      final start = _toCanvas(field, viewport, positions[i]);
      final end = _toCanvas(field, viewport, positions[i + 1]);
      for (int thickness = 10; thickness >= 4; thickness -= 3) {
        img.drawLine(
          canvas,
          x1: start.dx.round(),
          y1: start.dy.round(),
          x2: end.dx.round(),
          y2: end.dy.round(),
          color: thickness > 6 ? glow : gold,
          thickness: thickness,
        );
      }
    }

    for (int i = 0; i < view.waypointAnchors.length; i++) {
      final center = _toCanvas(field, viewport, view.waypointAnchors[i]);
      final fill = i == 0
          ? img.ColorRgb8(244, 211, 122)
          : i == view.waypointAnchors.length - 1
              ? img.ColorRgb8(255, 230, 166)
              : gold;
      img.fillCircle(
        canvas,
        x: center.dx.round(),
        y: center.dy.round(),
        radius: 14,
        color: fill,
      );
      for (int radius = 14; radius >= 12; radius--) {
        img.drawCircle(
          canvas,
          x: center.dx.round(),
          y: center.dy.round(),
          radius: radius,
          color: black,
        );
      }
    }

    for (final marker in view.markers) {
      final center = _toCanvas(field, viewport, marker.position);
      const size = 13;
      img.drawLine(
        canvas,
        x1: center.dx.round(),
        y1: center.dy.round() - size,
        x2: center.dx.round() + size,
        y2: center.dy.round(),
        color: glow,
        thickness: 3,
      );
      img.drawLine(
        canvas,
        x1: center.dx.round() + size,
        y1: center.dy.round(),
        x2: center.dx.round(),
        y2: center.dy.round() + size,
        color: glow,
        thickness: 3,
      );
      img.drawLine(
        canvas,
        x1: center.dx.round(),
        y1: center.dy.round() + size,
        x2: center.dx.round() - size,
        y2: center.dy.round(),
        color: glow,
        thickness: 3,
      );
      img.drawLine(
        canvas,
        x1: center.dx.round() - size,
        y1: center.dy.round(),
        x2: center.dx.round(),
        y2: center.dy.round() - size,
        color: glow,
        thickness: 3,
      );

      _drawAnchoredTag(
        canvas,
        anchorX: center.dx.round(),
        anchorY: center.dy.round(),
        text: _markerTimeLabel(marker),
        occupied: occupiedTags,
        large: true,
      );
    }
  }

  static void _paintInfoPanel(
    img.Image canvas,
    int fieldWidth,
    _ResolvedAutoView view,
  ) {
    final panelX = fieldWidth + 24;
    final panelWidth = canvas.width - panelX - 24;
    final panelColor = img.ColorRgb8(16, 16, 16);
    final outline = img.ColorRgb8(90, 72, 32);
    img.fillRect(
      canvas,
      x1: panelX,
      y1: 24,
      x2: panelX + panelWidth,
      y2: canvas.height - 24,
      color: panelColor,
      radius: 24,
    );
    img.drawRect(
      canvas,
      x1: panelX,
      y1: 24,
      x2: panelX + panelWidth,
      y2: canvas.height - 24,
      color: outline,
      thickness: 3,
      radius: 24,
    );

    int y = 60;
    y = _drawText(canvas, panelX + 24, y, view.name, size: 48, accent: true);
    y = _drawText(canvas, panelX + 24, y + 12, view.matchLabel, size: 36);
    y = _drawText(
      canvas,
      panelX + 24,
      y + 20,
      'Mirror: ${view.canMirror ? 'Yes' : 'No'}',
      size: 28,
    );
    y = _drawText(
      canvas,
      panelX + 24,
      y + 10,
      'Rotations: ${view.mirrorRotations.isEmpty ? 'None' : view.mirrorRotations.map((value) => '$value°').join(', ')}',
      size: 28,
    );
    y = _drawText(canvas, panelX + 24, y + 28, 'Pass To Center', size: 34);

    final trends = _buildPassTrends(view.allMatchPassTimes);
    for (int i = 0; i < 4; i++) {
      final value = view.passToCenterTimes[i];
      final average = trends[i].average;
      final trend = trends[i].label;
      y = _drawText(
        canvas,
        panelX + 36,
        y + 12,
        '${_passName(i)}: ${value == null ? 'n/a' : '${value.toStringAsFixed(2)}s'}'
        '  avg ${average == null ? 'n/a' : '${average.toStringAsFixed(2)}s'}'
        '  trend $trend',
        size: 28,
      );
    }

    y = _drawText(canvas, panelX + 24, y + 32, 'Path Timings', size: 34);
    for (int i = 0; i < view.waypointTimings.length; i++) {
      final label = i == 0
          ? 'Start'
          : i == view.waypointTimings.length - 1
              ? 'End'
              : 'Waypoint ${i + 1}';
      y = _drawText(
        canvas,
        panelX + 36,
        y + 12,
        '$label • ${_formatTime(view.waypointTimings[i])}',
        size: 28,
      );
    }

    if (view.markers.isNotEmpty) {
      y = _drawText(canvas, panelX + 24, y + 32, 'Path Markers', size: 34);
      for (final marker in view.markers) {
        y = _drawText(
          canvas,
          panelX + 36,
          y + 12,
          '${marker.label} • ${_formatTime(marker.timeSeconds)}',
          size: 28,
        );
      }
    }
  }

  static int _drawText(
    img.Image canvas,
    int x,
    int y,
    String text, {
    int size = 24,
    bool accent = false,
  }) {
    final font = size >= 44
        ? img.arial48
        : size >= 22
            ? img.arial24
            : img.arial14;
    img.drawString(
      canvas,
      text,
      x: x,
      y: y,
      font: font,
      color:
          accent ? img.ColorRgb8(244, 211, 122) : img.ColorRgb8(240, 233, 220),
    );
    return y + font.lineHeight;
  }

  static void _drawTag(
    img.Image canvas, {
    required int x,
    required int y,
    required String text,
    bool large = false,
  }) {
    final font = large ? img.arial48 : img.arial14;
    final paddingX = large ? 16 : 8;
    final paddingY = large ? 10 : 6;
    final width = max(96, text.length * (large ? 28 : 14));
    final height = font.lineHeight + (paddingY * 2);
    img.fillRect(
      canvas,
      x1: x - paddingX,
      y1: y - paddingY,
      x2: x + width,
      y2: y + height,
      color: img.ColorRgba8(0, 0, 0, 180),
      radius: 10,
    );
    img.drawString(
      canvas,
      text,
      x: x,
      y: y,
      font: font,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  static void _drawAnchoredTag(
    img.Image canvas, {
    required int anchorX,
    required int anchorY,
    required String text,
    required List<_LabelRect> occupied,
    bool large = false,
  }) {
    final font = large ? img.arial48 : img.arial14;
    final paddingX = large ? 16 : 8;
    final paddingY = large ? 10 : 6;
    final width = max(96, text.length * (large ? 28 : 14));
    final height = font.lineHeight + (paddingY * 2);
    final candidates = [
      ((anchorX + 28).toDouble(), (anchorY - height - 24).toDouble()),
      ((anchorX + 28).toDouble(), (anchorY + 18).toDouble()),
      ((anchorX - width - 28).toDouble(), (anchorY - height - 24).toDouble()),
      ((anchorX - width - 28).toDouble(), (anchorY + 18).toDouble()),
      ((anchorX + 48).toDouble(), (anchorY - (height ~/ 2)).toDouble()),
      ((anchorX - width - 48).toDouble(), (anchorY - (height ~/ 2)).toDouble()),
      ((anchorX - (width ~/ 2)).toDouble(), (anchorY - height - 34).toDouble()),
      ((anchorX - (width ~/ 2)).toDouble(), (anchorY + 26).toDouble()),
    ];

    _LabelRect chosen = _clampLabelRect(
      _LabelRect(
        x1: candidates.first.$1 - paddingX,
        y1: candidates.first.$2 - paddingY,
        x2: candidates.first.$1 + width,
        y2: candidates.first.$2 + height,
      ),
      canvas,
    );
    var bestScore = double.infinity;

    for (final candidate in candidates) {
      final rect = _clampLabelRect(
        _LabelRect(
          x1: candidate.$1 - paddingX,
          y1: candidate.$2 - paddingY,
          x2: candidate.$1 + width,
          y2: candidate.$2 + height,
        ),
        canvas,
      );
      final overlaps =
          occupied.where((other) => rect.overlaps(other)).length.toDouble();
      final centerX = (rect.x1 + rect.x2) / 2.0;
      final centerY = (rect.y1 + rect.y2) / 2.0;
      final distance = pow(centerX - anchorX, 2) + pow(centerY - anchorY, 2);
      final score = (overlaps * 1000000) + distance;
      if (score < bestScore) {
        bestScore = score;
        chosen = rect;
      }
    }

    occupied.add(chosen);

    final tagTextX = chosen.x1 + paddingX;
    final tagTextY = chosen.y1 + paddingY;
    _drawTag(
      canvas,
      x: tagTextX.round(),
      y: tagTextY.round(),
      text: text,
      large: large,
    );

    final labelAnchor = _closestPointOnRect(
      chosen,
      anchorX.toDouble(),
      anchorY.toDouble(),
    );
    img.drawLine(
      canvas,
      x1: anchorX,
      y1: anchorY,
      x2: labelAnchor.dx.round(),
      y2: labelAnchor.dy.round(),
      color: img.ColorRgb8(255, 255, 255),
      thickness: large ? 3 : 2,
    );
  }

  static _LabelRect _clampLabelRect(_LabelRect rect, img.Image canvas) {
    final dx = rect.x1 < 12
        ? 12 - rect.x1
        : rect.x2 > canvas.width - 12
            ? (canvas.width - 12) - rect.x2
            : 0.0;
    final dy = rect.y1 < 12
        ? 12 - rect.y1
        : rect.y2 > canvas.height - 12
            ? (canvas.height - 12) - rect.y2
            : 0.0;
    return rect.shift(dx, dy);
  }

  static _PixelPoint _closestPointOnRect(
    _LabelRect rect,
    double x,
    double y,
  ) {
    return _PixelPoint(
      x.clamp(rect.x1, rect.x2).toDouble(),
      y.clamp(rect.y1, rect.y2).toDouble(),
    );
  }

  static List<_PassTrend> _buildPassTrends(
      List<List<double?>> allMatchPassTimes) {
    return List<_PassTrend>.generate(4, (index) {
      final values = allMatchPassTimes
          .map((entry) => entry[index])
          .whereType<double>()
          .toList(growable: false);
      if (values.isEmpty) {
        return const _PassTrend(average: null, label: 'n/a');
      }

      final average = values.reduce((a, b) => a + b) / values.length;
      if (values.length < 2) {
        return _PassTrend(average: average, label: 'flat');
      }

      final delta = values.last - values.first;
      final label = delta.abs() < 0.05
          ? 'flat'
          : delta < 0
              ? 'down'
              : 'up';
      return _PassTrend(average: average, label: label);
    });
  }

  static String _passName(int index) {
    switch (index) {
      case 0:
        return 'First pass';
      case 1:
        return 'Second pass';
      case 2:
        return 'Third pass';
      default:
        return 'Fourth pass';
    }
  }

  static String _formatTime(double? timeSeconds) {
    return timeSeconds == null ? 'n/a' : '${timeSeconds.toStringAsFixed(2)}s';
  }

  static String _markerTimeLabel(_TimedMarker marker) {
    final time = _formatTime(marker.timeSeconds);
    return marker.label.isEmpty ? time : '${marker.label}  $time';
  }

  static _PixelPoint _toCanvas(
    _ServerFieldSpec field,
    _FieldViewport viewport,
    _Point point,
  ) {
    final x = ((point.x + field.marginMeters) / field.totalWidthMeters) *
            field.imageWidth -
        viewport.x;
    final y = field.imageHeight -
        (((point.y + field.marginMeters) / field.totalHeightMeters) *
            field.imageHeight);
    return _PixelPoint(x, y);
  }
}

class _FieldViewport {
  static const double _visibleFraction = 0.6;

  final int x;
  final int width;
  final int fullWidth;

  const _FieldViewport({
    required this.x,
    required this.width,
    required this.fullWidth,
  });

  bool get isFullWidth => x == 0 && width == fullWidth;

  factory _FieldViewport.forView(
    _ServerFieldSpec field,
    _ResolvedAutoView view,
  ) {
    final content = [
      ...view.sampledPathPositions,
      ...view.waypointAnchors,
      for (final marker in view.markers) marker.position,
    ];

    if (content.isEmpty) {
      return _FieldViewport(
        x: 0,
        width: field.imageWidth,
        fullWidth: field.imageWidth,
      );
    }

    final centerX = content.map((point) => point.x).reduce((a, b) => a + b) /
        content.length;
    final visibleWidth = (field.imageWidth * _visibleFraction).round();
    final showLeftSide = centerX <= field.widthMeters / 2.0;
    return _FieldViewport(
      x: showLeftSide ? 0 : field.imageWidth - visibleWidth,
      width: visibleWidth,
      fullWidth: field.imageWidth,
    );
  }
}

class _ResolvedAutoView {
  final String fieldId;
  final String name;
  final String matchId;
  final String matchLabel;
  final bool canMirror;
  final List<int> mirrorRotations;
  final List<double?> waypointTimings;
  final List<_TimedMarker> markers;
  final List<double?> passToCenterTimes;
  final List<List<double?>> allMatchPassTimes;
  final List<_Point> waypointAnchors;
  final List<_Point> sampledPathPositions;

  const _ResolvedAutoView({
    required this.fieldId,
    required this.name,
    required this.matchId,
    required this.matchLabel,
    required this.canMirror,
    required this.mirrorRotations,
    required this.waypointTimings,
    required this.markers,
    required this.passToCenterTimes,
    required this.allMatchPassTimes,
    required this.waypointAnchors,
    required this.sampledPathPositions,
  });

  factory _ResolvedAutoView.fromJson(
    Map<String, dynamic> autoJson, {
    String? requestedMatchId,
  }) {
    final matches = _rawMatches(autoJson);
    final selectedMatchId =
        requestedMatchId ?? autoJson['selectedMatchId'] as String? ?? 'match_1';
    final match = matches.firstWhere(
      (entry) => entry['id'] == selectedMatchId,
      orElse: () => matches.firstOrNull ?? _legacyMatch(autoJson),
    );

    final points = _rawPoints(autoJson);
    final pointTimingById = {
      for (final entry
          in (match['markerTimings'] as List<dynamic>? ?? const []))
        (entry as Map)['markerId'] as String? ?? '': Map<String, dynamic>.from(
          entry,
        ),
    };

    final rawMarkers = [
      for (final point in points)
        _TimedMarker(
          id: point['id'] as String? ?? 'marker',
          position: _Point.fromJson(
            Map<String, dynamic>.from(point['position'] as Map),
          ),
          timeSeconds:
              ((pointTimingById[point['id']]?['timeSeconds'] as num?) ??
                      (point['timeSeconds'] as num?))
                  ?.toDouble(),
          isToCenter:
              pointTimingById[point['id']]?['isToCenter'] as bool? ?? false,
          passNumber:
              (pointTimingById[point['id']]?['passNumber'] as num?)?.toInt(),
          label: (pointTimingById[point['id']]?['name'] as String? ??
                  point['note'] as String? ??
                  '')
              .trim(),
        ),
    ]..sort((a, b) => _sortTime(a.timeSeconds).compareTo(
          _sortTime(b.timeSeconds),
        ));

    final markers = <_TimedMarker>[];
    int genericMarkerCount = 0;
    for (final marker in rawMarkers) {
      genericMarkerCount++;
      markers.add(
        marker.copyWith(
          label: marker.label.isNotEmpty
              ? marker.label
              : marker.isToCenter
                  ? 'Pass ${marker.passNumber ?? 1} To Center'
                  : 'Timestamp $genericMarkerCount',
        ),
      );
    }

    final waypointTimings =
        (match['waypointTimings'] as List<dynamic>? ?? const [])
            .map((entry) => ((entry as Map)['timeSeconds'] as num?)?.toDouble())
            .toList(growable: false);

    final allMatchPassTimes = [
      for (final item in matches)
        _normalizePassTimes(
          (item['passToCenterTimes'] as List<dynamic>? ?? const [])
              .map((value) => (value as num?)?.toDouble())
              .toList(growable: false),
        ),
    ];

    final pathWaypoints = _rawPathWaypoints(autoJson);
    final waypointAnchors = pathWaypoints
        .map((entry) =>
            _Point.fromJson(Map<String, dynamic>.from(entry['anchor'] as Map)))
        .toList(growable: false);

    final sampledPathPositions = pathWaypoints.length >= 2
        ? _samplePath(pathWaypoints)
        : markers.map((marker) => marker.position).toList(growable: false);

    return _ResolvedAutoView(
      fieldId: autoJson['fieldId'] as String? ?? 'rebuilt',
      name: autoJson['name'] as String? ?? 'Untitled Auto',
      matchId: match['id'] as String? ?? 'match_1',
      matchLabel: _matchLabel(match),
      canMirror: autoJson['canMirror'] as bool? ?? false,
      mirrorRotations: _normalizeRotations(
        (autoJson['mirrorRotations'] as List<dynamic>? ?? const [])
            .map((value) => (value as num?)?.toInt())
            .whereType<int>()
            .toList(growable: false),
      ),
      waypointTimings: waypointTimings,
      markers: markers,
      passToCenterTimes: _normalizePassTimes(
        (match['passToCenterTimes'] as List<dynamic>? ?? const [])
            .map((value) => (value as num?)?.toDouble())
            .toList(growable: false),
      ),
      allMatchPassTimes: allMatchPassTimes.isEmpty
          ? [
              const [null, null, null, null]
            ]
          : allMatchPassTimes,
      waypointAnchors: waypointAnchors,
      sampledPathPositions: sampledPathPositions,
    );
  }

  static List<Map<String, dynamic>> _rawMatches(Map<String, dynamic> autoJson) {
    final matches = (autoJson['matches'] as List<dynamic>? ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    if (matches.isNotEmpty) {
      return matches;
    }
    return [_legacyMatch(autoJson)];
  }

  static Map<String, dynamic> _legacyMatch(Map<String, dynamic> autoJson) {
    return {
      'id': 'match_1',
      'matchNumber': '1',
      'label': '',
      'waypointTimings': autoJson['waypointTimings'] ?? const [],
      'markerTimings': [
        for (final point in _rawPoints(autoJson))
          {
            'markerId': point['id'],
            if (point['timeSeconds'] != null)
              'timeSeconds': point['timeSeconds'],
            'name': point['note'] ?? '',
          },
      ],
      'passToCenterTimes': const [null, null, null, null],
    };
  }

  static List<Map<String, dynamic>> _rawPoints(Map<String, dynamic> autoJson) {
    return (autoJson['points'] as List<dynamic>? ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _rawPathWaypoints(
      Map<String, dynamic> autoJson) {
    final path = autoJson['path'];
    if (path is Map<String, dynamic>) {
      return (path['waypoints'] as List<dynamic>? ?? const [])
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(growable: false);
    }
    return const [];
  }

  static List<_Point> _samplePath(List<Map<String, dynamic>> waypoints) {
    final samples = <_Point>[];
    for (int i = 0; i < waypoints.length - 1; i++) {
      final current = waypoints[i];
      final next = waypoints[i + 1];
      final p0 =
          _Point.fromJson(Map<String, dynamic>.from(current['anchor'] as Map));
      final p1 = current['nextControl'] == null
          ? p0
          : _Point.fromJson(
              Map<String, dynamic>.from(current['nextControl'] as Map),
            );
      final p2 = next['prevControl'] == null
          ? _Point.fromJson(Map<String, dynamic>.from(next['anchor'] as Map))
          : _Point.fromJson(
              Map<String, dynamic>.from(next['prevControl'] as Map),
            );
      final p3 =
          _Point.fromJson(Map<String, dynamic>.from(next['anchor'] as Map));

      for (int step = 0; step <= 40; step++) {
        final t = step / 40.0;
        samples.add(_cubic(p0, p1, p2, p3, t));
      }
    }
    return samples;
  }

  static _Point _cubic(
    _Point p0,
    _Point p1,
    _Point p2,
    _Point p3,
    double t,
  ) {
    final omt = 1 - t;
    final x = (omt * omt * omt * p0.x) +
        (3 * omt * omt * t * p1.x) +
        (3 * omt * t * t * p2.x) +
        (t * t * t * p3.x);
    final y = (omt * omt * omt * p0.y) +
        (3 * omt * omt * t * p1.y) +
        (3 * omt * t * t * p2.y) +
        (t * t * t * p3.y);
    return _Point(x, y);
  }

  static String _matchLabel(Map<String, dynamic> match) {
    final matchNumber = _displayMatchNumber(
      match['matchNumber'] as String? ?? '',
    );
    if (matchNumber.isNotEmpty) {
      return matchNumber;
    }

    final label = _displayMatchNumber(match['label'] as String? ?? '');
    return label.isEmpty ? '1' : label;
  }

  static String _displayMatchNumber(String value) {
    final trimmed = value.trim();
    final matchPrefix = RegExp(r'^match\s+', caseSensitive: false);
    return trimmed.replaceFirst(matchPrefix, '').trim();
  }
}

class _TimedMarker {
  final String id;
  final _Point position;
  final double? timeSeconds;
  final bool isToCenter;
  final int? passNumber;
  final String label;

  const _TimedMarker({
    required this.id,
    required this.position,
    required this.timeSeconds,
    this.isToCenter = false,
    this.passNumber,
    this.label = '',
  });

  _TimedMarker copyWith({
    String? id,
    _Point? position,
    Object? timeSeconds = _unchanged,
    bool? isToCenter,
    int? passNumber,
    String? label,
  }) {
    return _TimedMarker(
      id: id ?? this.id,
      position: position ?? this.position,
      timeSeconds:
          timeSeconds == _unchanged ? this.timeSeconds : timeSeconds as double?,
      isToCenter: isToCenter ?? this.isToCenter,
      passNumber: passNumber ?? this.passNumber,
      label: label ?? this.label,
    );
  }
}

class _PassTrend {
  final double? average;
  final String label;

  const _PassTrend({
    required this.average,
    required this.label,
  });
}

class _Point {
  final double x;
  final double y;

  const _Point(this.x, this.y);

  factory _Point.fromJson(Map<String, dynamic> json) {
    return _Point(
      (json['x'] as num?)?.toDouble() ?? 0,
      (json['y'] as num?)?.toDouble() ?? 0,
    );
  }
}

class _PixelPoint {
  final double dx;
  final double dy;

  const _PixelPoint(this.dx, this.dy);
}

class _LabelRect {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const _LabelRect({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  bool overlaps(_LabelRect other) {
    return x1 < other.x2 && x2 > other.x1 && y1 < other.y2 && y2 > other.y1;
  }

  _LabelRect shift(double dx, double dy) {
    return _LabelRect(
      x1: x1 + dx,
      y1: y1 + dy,
      x2: x2 + dx,
      y2: y2 + dy,
    );
  }
}

class _ServerFieldSpec {
  final String id;
  final String assetPath;
  final int imageWidth;
  final int imageHeight;
  final double pixelsPerMeter;
  final double marginMeters;

  const _ServerFieldSpec({
    required this.id,
    required this.assetPath,
    required this.imageWidth,
    required this.imageHeight,
    required this.pixelsPerMeter,
    this.marginMeters = 0,
  });

  double get widthMeters => (imageWidth / pixelsPerMeter) - (marginMeters * 2);
  double get heightMeters =>
      (imageHeight / pixelsPerMeter) - (marginMeters * 2);
  double get totalWidthMeters => widthMeters + (marginMeters * 2);
  double get totalHeightMeters => heightMeters + (marginMeters * 2);

  static const _fields = [
    _ServerFieldSpec(
      id: 'rapid-react',
      assetPath: 'images/field22.png',
      imageWidth: 3240,
      imageHeight: 1620,
      pixelsPerMeter: 196.85,
    ),
    _ServerFieldSpec(
      id: 'charged-up',
      assetPath: 'images/field23.png',
      imageWidth: 3256,
      imageHeight: 1578,
      pixelsPerMeter: 196.85,
    ),
    _ServerFieldSpec(
      id: 'crescendo',
      assetPath: 'images/field24.png',
      imageWidth: 3256,
      imageHeight: 1616,
      pixelsPerMeter: 196.85,
    ),
    _ServerFieldSpec(
      id: 'reefscape',
      assetPath: 'images/field25.png',
      imageWidth: 3510,
      imageHeight: 1610,
      pixelsPerMeter: 200,
    ),
    _ServerFieldSpec(
      id: 'reefscape-annotated',
      assetPath: 'images/field25-annotated.png',
      imageWidth: 3510,
      imageHeight: 1610,
      pixelsPerMeter: 200,
    ),
    _ServerFieldSpec(
      id: 'rebuilt',
      assetPath: 'images/field26.png',
      imageWidth: 3508,
      imageHeight: 1814,
      pixelsPerMeter: 200,
      marginMeters: 0.5,
    ),
  ];

  static _ServerFieldSpec byId(String? id) {
    return _fields.firstWhere(
      (field) => field.id == id,
      orElse: () => _fields.last,
    );
  }
}

List<double?> _normalizePassTimes(List<double?> values) {
  return List<double?>.generate(
    4,
    (index) => index < values.length ? values[index] : null,
    growable: false,
  );
}

List<int> _normalizeRotations(List<int> values) {
  final allowed = {0, 90, 180, 270};
  final normalized = <int>{};
  for (final value in values) {
    if (allowed.contains(value)) {
      normalized.add(value);
    }
  }
  final result = normalized.toList()..sort();
  return result;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
