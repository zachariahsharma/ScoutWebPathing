import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ObservedAutoExport {
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

    final canvasWidth = fieldImage.width + 560;
    final canvasHeight = max(fieldImage.height, 1600);
    final canvas = img.Image(
      width: canvasWidth,
      height: canvasHeight,
      numChannels: 4,
    );

    img.fill(canvas, color: img.ColorRgb8(5, 5, 5));
    img.compositeImage(canvas, fieldImage, dstX: 0, dstY: 0);
    _paintPath(canvas, field, view);
    _paintInfoPanel(canvas, fieldImage.width, view);

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
    _ResolvedAutoView view,
  ) {
    final positions = view.sampledPathPositions;
    if (positions.isEmpty) {
      return;
    }

    final gold = img.ColorRgb8(212, 164, 55);
    final glow = img.ColorRgb8(244, 211, 122);
    final black = img.ColorRgb8(8, 8, 8);

    for (int i = 0; i < positions.length - 1; i++) {
      final start = _toCanvas(field, positions[i]);
      final end = _toCanvas(field, positions[i + 1]);
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
      final center = _toCanvas(field, view.waypointAnchors[i]);
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

      if (i < view.waypointTimings.length) {
        _drawTag(
          canvas,
          x: center.dx.round() + 18,
          y: center.dy.round() - 36,
          text:
              '${_waypointName(i, view.waypointAnchors.length)}  ${view.waypointTimings[i].toStringAsFixed(2)}s',
          large: true,
        );
      }
    }

    for (final marker in view.markers) {
      final center = _toCanvas(field, marker.position);
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

      _drawTag(
        canvas,
        x: center.dx.round() + 18,
        y: center.dy.round() + 10,
        text: '${marker.label}  ${marker.timeSeconds.toStringAsFixed(2)}s',
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
    y = _drawText(canvas, panelX + 24, y + 10, view.matchLabel, size: 30);
    y = _drawText(
      canvas,
      panelX + 24,
      y + 18,
      'Mirror: ${view.canMirror ? 'Yes' : 'No'}',
      size: 24,
    );
    y = _drawText(
      canvas,
      panelX + 24,
      y + 6,
      'Rotations: ${view.mirrorRotations.isEmpty ? 'None' : view.mirrorRotations.map((value) => '$value°').join(', ')}',
      size: 24,
    );
    y = _drawText(canvas, panelX + 24, y + 24, 'Pass To Center', size: 28);

    final trends = _buildPassTrends(view.allMatchPassTimes);
    for (int i = 0; i < 4; i++) {
      final value = view.passToCenterTimes[i];
      final average = trends[i].average;
      final trend = trends[i].label;
      y = _drawText(
        canvas,
        panelX + 36,
        y + 10,
        '${_passName(i)}: ${value == null ? 'n/a' : '${value.toStringAsFixed(2)}s'}'
        '  avg ${average == null ? 'n/a' : '${average.toStringAsFixed(2)}s'}'
        '  trend $trend',
        size: 22,
      );
    }

    y = _drawText(canvas, panelX + 24, y + 28, 'Path Timings', size: 28);
    for (int i = 0; i < view.waypointTimings.length; i++) {
      final label = i == 0
          ? 'Start'
          : i == view.waypointTimings.length - 1
              ? 'End'
              : 'Waypoint ${i + 1}';
      y = _drawText(
        canvas,
        panelX + 36,
        y + 10,
        '$label • ${view.waypointTimings[i].toStringAsFixed(2)}s',
        size: 22,
      );
    }

    if (view.markers.isNotEmpty) {
      y = _drawText(canvas, panelX + 24, y + 28, 'Path Markers', size: 28);
      for (final marker in view.markers) {
        y = _drawText(
          canvas,
          panelX + 36,
          y + 10,
          '${marker.label} • ${marker.timeSeconds.toStringAsFixed(2)}s',
          size: 22,
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
        : size >= 28
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
    final font = large ? img.arial24 : img.arial14;
    final paddingX = large ? 16 : 8;
    final paddingY = large ? 10 : 6;
    final width = max(96, text.length * (large ? 22 : 14));
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

  static String _waypointName(int index, int count) {
    if (index == 0) {
      return 'Start';
    }
    if (index == count - 1) {
      return 'End';
    }
    return 'Waypoint ${index + 1}';
  }

  static _PixelPoint _toCanvas(_ServerFieldSpec field, _Point point) {
    final x = ((point.x + field.marginMeters) / field.totalWidthMeters) *
        field.imageWidth;
    final y = field.imageHeight -
        (((point.y + field.marginMeters) / field.totalHeightMeters) *
            field.imageHeight);
    return _PixelPoint(x, y);
  }
}

class _ResolvedAutoView {
  final String fieldId;
  final String name;
  final String matchId;
  final String matchLabel;
  final bool canMirror;
  final List<int> mirrorRotations;
  final List<double> waypointTimings;
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
                      (point['timeSeconds'] as num?) ??
                      0)
                  .toDouble(),
          isToCenter:
              pointTimingById[point['id']]?['isToCenter'] as bool? ?? false,
          passNumber:
              (pointTimingById[point['id']]?['passNumber'] as num?)?.toInt(),
        ),
    ]..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    final markers = <_TimedMarker>[];
    int genericMarkerCount = 0;
    for (final marker in rawMarkers) {
      genericMarkerCount++;
      markers.add(
        marker.copyWith(
          label: marker.isToCenter
              ? 'Pass ${marker.passNumber ?? 1} To Center'
              : 'Timestamp $genericMarkerCount',
        ),
      );
    }

    final waypointTimings =
        (match['waypointTimings'] as List<dynamic>? ?? const [])
            .map((entry) =>
                ((entry as Map)['timeSeconds'] as num?)?.toDouble() ?? 0.0)
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
      'matchNumber': 'Match 1',
      'label': 'Match 1',
      'waypointTimings': autoJson['waypointTimings'] ?? const [],
      'markerTimings': [
        for (final point in _rawPoints(autoJson))
          {
            'markerId': point['id'],
            'timeSeconds': point['timeSeconds'] ?? 0,
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
    final matchNumber = (match['matchNumber'] as String? ?? '').trim();
    final label = (match['label'] as String? ?? '').trim();

    if (matchNumber.isEmpty && label.isEmpty) {
      return 'Match';
    }
    if (matchNumber.isEmpty) {
      return label;
    }
    if (label.isEmpty || matchNumber.toLowerCase() == label.toLowerCase()) {
      return matchNumber;
    }
    return '$matchNumber - $label';
  }
}

class _TimedMarker {
  final String id;
  final _Point position;
  final double timeSeconds;
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
    double? timeSeconds,
    bool? isToCenter,
    int? passNumber,
    String? label,
  }) {
    return _TimedMarker(
      id: id ?? this.id,
      position: position ?? this.position,
      timeSeconds: timeSeconds ?? this.timeSeconds,
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
