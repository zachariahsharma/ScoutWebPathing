import 'dart:convert';

import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/webui/models/observed_field.dart';

class ObservedAutoPoint {
  final String id;
  final Translation2d position;
  final double? waypointRelativePos;
  final double timeSeconds;
  final String note;
  final bool isToCenter;
  final int? passNumber;

  const ObservedAutoPoint({
    required this.id,
    required this.position,
    this.waypointRelativePos,
    required this.timeSeconds,
    this.note = '',
    this.isToCenter = false,
    this.passNumber,
  });

  ObservedAutoPoint copyWith({
    String? id,
    Translation2d? position,
    double? waypointRelativePos,
    double? timeSeconds,
    String? note,
    bool? isToCenter,
    int? passNumber,
  }) {
    return ObservedAutoPoint(
      id: id ?? this.id,
      position: position ?? this.position,
      waypointRelativePos: waypointRelativePos ?? this.waypointRelativePos,
      timeSeconds: timeSeconds ?? this.timeSeconds,
      note: note ?? this.note,
      isToCenter: isToCenter ?? this.isToCenter,
      passNumber: passNumber ?? this.passNumber,
    );
  }

  factory ObservedAutoPoint.fromJson(Map<String, dynamic> json) {
    return ObservedAutoPoint(
      id: json['id'] as String? ?? '',
      position: Translation2d.fromJson(
        json['position'] as Map<String, dynamic>,
      ),
      waypointRelativePos: (json['waypointRelativePos'] as num?)?.toDouble(),
      timeSeconds: (json['timeSeconds'] as num?)?.toDouble() ?? 0,
      note: json['note'] as String? ?? '',
      isToCenter: json['isToCenter'] as bool? ?? false,
      passNumber: (json['passNumber'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'position': position.toJson(),
      'waypointRelativePos': waypointRelativePos,
      'timeSeconds': timeSeconds,
      'note': note,
      'isToCenter': isToCenter,
      'passNumber': passNumber,
    };
  }
}

class ObservedWaypointTiming {
  final double timeSeconds;
  final String note;

  const ObservedWaypointTiming({
    required this.timeSeconds,
    this.note = '',
  });

  ObservedWaypointTiming copyWith({
    double? timeSeconds,
    String? note,
  }) {
    return ObservedWaypointTiming(
      timeSeconds: timeSeconds ?? this.timeSeconds,
      note: note ?? this.note,
    );
  }

  factory ObservedWaypointTiming.fromJson(Map<String, dynamic> json) {
    return ObservedWaypointTiming(
      timeSeconds: (json['timeSeconds'] as num?)?.toDouble() ?? 0,
      note: json['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timeSeconds': timeSeconds,
      'note': note,
    };
  }
}

class ObservedMarkerTiming {
  final String markerId;
  final double timeSeconds;
  final bool isToCenter;
  final int? passNumber;

  const ObservedMarkerTiming({
    required this.markerId,
    required this.timeSeconds,
    this.isToCenter = false,
    this.passNumber,
  });

  ObservedMarkerTiming copyWith({
    String? markerId,
    double? timeSeconds,
    bool? isToCenter,
    int? passNumber,
  }) {
    return ObservedMarkerTiming(
      markerId: markerId ?? this.markerId,
      timeSeconds: timeSeconds ?? this.timeSeconds,
      isToCenter: isToCenter ?? this.isToCenter,
      passNumber: passNumber ?? this.passNumber,
    );
  }

  factory ObservedMarkerTiming.fromJson(Map<String, dynamic> json) {
    return ObservedMarkerTiming(
      markerId: json['markerId'] as String? ?? '',
      timeSeconds: (json['timeSeconds'] as num?)?.toDouble() ?? 0,
      isToCenter: json['isToCenter'] as bool? ?? false,
      passNumber: (json['passNumber'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'markerId': markerId,
      'timeSeconds': timeSeconds,
      'isToCenter': isToCenter,
      'passNumber': passNumber,
    };
  }
}

class ObservedMatchObservation {
  final String id;
  final String matchNumber;
  final String label;
  final List<ObservedWaypointTiming> waypointTimings;
  final List<ObservedMarkerTiming> markerTimings;
  final List<double?> passToCenterTimes;

  const ObservedMatchObservation({
    required this.id,
    this.matchNumber = '',
    required this.label,
    this.waypointTimings = const [],
    this.markerTimings = const [],
    this.passToCenterTimes = const [null, null, null, null],
  });

  ObservedMatchObservation copyWith({
    String? id,
    String? matchNumber,
    String? label,
    List<ObservedWaypointTiming>? waypointTimings,
    List<ObservedMarkerTiming>? markerTimings,
    List<double?>? passToCenterTimes,
  }) {
    return ObservedMatchObservation(
      id: id ?? this.id,
      matchNumber: matchNumber ?? this.matchNumber,
      label: label ?? this.label,
      waypointTimings: waypointTimings ?? this.waypointTimings,
      markerTimings: markerTimings ?? this.markerTimings,
      passToCenterTimes: passToCenterTimes ?? this.passToCenterTimes,
    );
  }

  factory ObservedMatchObservation.fromJson(Map<String, dynamic> json) {
    return ObservedMatchObservation(
      id: json['id'] as String? ?? '',
      matchNumber: json['matchNumber'] as String? ?? '',
      label: json['label'] as String? ?? 'Match',
      waypointTimings: (json['waypointTimings'] as List<dynamic>? ?? const [])
          .map((timing) => ObservedWaypointTiming.fromJson(
              Map<String, dynamic>.from(timing as Map)))
          .toList(),
      markerTimings: (json['markerTimings'] as List<dynamic>? ?? const [])
          .map((timing) => ObservedMarkerTiming.fromJson(
              Map<String, dynamic>.from(timing as Map)))
          .toList(),
      passToCenterTimes: _normalizePassTimes(
        (json['passToCenterTimes'] as List<dynamic>? ?? const [])
            .map((value) => (value as num?)?.toDouble())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'matchNumber': matchNumber,
      'label': label,
      'waypointTimings': [
        for (final timing in waypointTimings) timing.toJson(),
      ],
      'markerTimings': [
        for (final timing in markerTimings) timing.toJson(),
      ],
      'passToCenterTimes': [
        for (final value in _normalizePassTimes(passToCenterTimes)) value,
      ],
    };
  }

  ObservedMatchObservation normalizedFor({
    required int waypointCount,
    required List<ObservedAutoPoint> markers,
    required List<ObservedWaypointTiming> fallbackWaypointTimings,
  }) {
    final nextWaypointTimings = <ObservedWaypointTiming>[];
    for (int i = 0; i < waypointCount; i++) {
      if (i < waypointTimings.length) {
        nextWaypointTimings.add(waypointTimings[i]);
      } else if (i < fallbackWaypointTimings.length) {
        nextWaypointTimings.add(fallbackWaypointTimings[i]);
      } else if (nextWaypointTimings.isEmpty) {
        nextWaypointTimings.add(const ObservedWaypointTiming(timeSeconds: 0));
      } else {
        nextWaypointTimings.add(
          ObservedWaypointTiming(
            timeSeconds: nextWaypointTimings.last.timeSeconds + 1,
          ),
        );
      }
    }

    final markerTimeById = {
      for (final timing in markerTimings) timing.markerId: timing,
    };
    final nextMarkerTimings = [
      for (final marker in markers)
        if (markerTimeById.containsKey(marker.id))
          markerTimeById[marker.id]!.copyWith(
            timeSeconds: markerTimeById[marker.id]!.timeSeconds,
          )
        else
          ObservedMarkerTiming(
            markerId: marker.id,
            timeSeconds: marker.timeSeconds,
            isToCenter: marker.isToCenter,
            passNumber: marker.passNumber,
          ),
    ];

    final nextPassTimes = List<double?>.filled(4, null, growable: false);
    for (final timing in nextMarkerTimings) {
      final index = timing.passNumber == null ? null : timing.passNumber! - 1;
      if (timing.isToCenter && index != null && index >= 0 && index < 4) {
        final existing = nextPassTimes[index];
        if (existing == null || timing.timeSeconds < existing) {
          nextPassTimes[index] = timing.timeSeconds;
        }
      }
    }

    return copyWith(
      waypointTimings: nextWaypointTimings,
      markerTimings: nextMarkerTimings,
      passToCenterTimes: nextPassTimes,
    );
  }

  String get displayLabel {
    final trimmedNumber = matchNumber.trim();
    final trimmedLabel = label.trim();

    if (trimmedNumber.isEmpty && trimmedLabel.isEmpty) {
      return 'Match';
    }
    if (trimmedNumber.isEmpty) {
      return trimmedLabel;
    }
    if (trimmedLabel.isEmpty) {
      return trimmedNumber;
    }
    if (trimmedNumber.toLowerCase() == trimmedLabel.toLowerCase()) {
      return trimmedLabel;
    }
    return '$trimmedNumber - $trimmedLabel';
  }
}

class ObservedAutoSummary {
  final String id;
  final String name;
  final String updatedAt;
  final String fieldId;
  final List<ObservedAutoPoint> points;
  final List<ObservedWaypointTiming> waypointTimings;
  final Map<String, dynamic>? pathData;
  final bool canMirror;
  final List<int> mirrorRotations;
  final List<ObservedMatchObservation> matches;
  final String? selectedMatchId;

  const ObservedAutoSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.fieldId,
    this.points = const [],
    this.waypointTimings = const [],
    this.pathData,
    this.canMirror = false,
    this.mirrorRotations = const [],
    this.matches = const [],
    this.selectedMatchId,
  });

  factory ObservedAutoSummary.fromJson(Map<String, dynamic> json) {
    final pointsJson = (json['points'] as List<dynamic>? ?? const [])
        .map((point) => Map<String, dynamic>.from(point as Map))
        .toList();
    return ObservedAutoSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Auto',
      updatedAt: json['updatedAt'] as String? ?? '',
      fieldId: json['fieldId'] as String? ??
          ObservedFieldSpec.officialFields.last.id,
      points: pointsJson.map(ObservedAutoPoint.fromJson).toList(),
      waypointTimings: (json['waypointTimings'] as List<dynamic>? ?? const [])
          .map((timing) => ObservedWaypointTiming.fromJson(
              Map<String, dynamic>.from(timing as Map)))
          .toList(),
      pathData: json['path'] == null
          ? null
          : Map<String, dynamic>.from(json['path'] as Map),
      canMirror: json['canMirror'] as bool? ?? false,
      mirrorRotations: _normalizedMirrorRotations(
        (json['mirrorRotations'] as List<dynamic>? ?? const [])
            .map((value) => (value as num?)?.toInt())
            .whereType<int>()
            .toList(),
      ),
      matches: (json['matches'] as List<dynamic>? ?? const [])
          .map((match) => ObservedMatchObservation.fromJson(
              Map<String, dynamic>.from(match as Map)))
          .toList(),
      selectedMatchId: json['selectedMatchId'] as String?,
    );
  }

  ObservedAuto toPreviewAuto(String team) {
    return ObservedAuto(
      storageId: id,
      team: team,
      name: name,
      fieldId: fieldId,
      createdAt: updatedAt,
      updatedAt: updatedAt,
      points: points,
      waypointTimings: waypointTimings,
      pathData: pathData,
      canMirror: canMirror,
      mirrorRotations: mirrorRotations,
      matches: matches,
      selectedMatchId: selectedMatchId,
    ).sorted();
  }
}

class ObservedAuto {
  static const String defaultMatchId = 'match_1';

  final String storageId;
  final String team;
  final String name;
  final String fieldId;
  final String createdAt;
  final String updatedAt;
  final List<ObservedAutoPoint> points;
  final List<ObservedWaypointTiming> waypointTimings;
  final Map<String, dynamic>? pathData;
  final bool canMirror;
  final List<int> mirrorRotations;
  final List<ObservedMatchObservation> matches;
  final String? selectedMatchId;

  const ObservedAuto({
    required this.storageId,
    required this.team,
    required this.name,
    required this.fieldId,
    required this.createdAt,
    required this.updatedAt,
    required this.points,
    this.waypointTimings = const [],
    this.pathData,
    this.canMirror = false,
    this.mirrorRotations = const [],
    this.matches = const [],
    this.selectedMatchId,
  });

  factory ObservedAuto.empty({
    required String team,
    String name = 'New Auto',
    String fieldId = 'rebuilt',
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    const defaultTimings = [
      ObservedWaypointTiming(timeSeconds: 0),
      ObservedWaypointTiming(timeSeconds: 1.5),
    ];

    return ObservedAuto(
      storageId: '',
      team: team,
      name: name,
      fieldId: fieldId,
      createdAt: now,
      updatedAt: now,
      points: const [],
      waypointTimings: defaultTimings,
      matches: const [
        ObservedMatchObservation(
          id: defaultMatchId,
          matchNumber: 'Match 1',
          label: 'Match 1',
          waypointTimings: defaultTimings,
        ),
      ],
      selectedMatchId: defaultMatchId,
    ).sorted();
  }

  ObservedAuto copyWith({
    String? storageId,
    String? team,
    String? name,
    String? fieldId,
    String? createdAt,
    String? updatedAt,
    List<ObservedAutoPoint>? points,
    List<ObservedWaypointTiming>? waypointTimings,
    Map<String, dynamic>? pathData,
    bool? canMirror,
    List<int>? mirrorRotations,
    List<ObservedMatchObservation>? matches,
    String? selectedMatchId,
  }) {
    return ObservedAuto(
      storageId: storageId ?? this.storageId,
      team: team ?? this.team,
      name: name ?? this.name,
      fieldId: fieldId ?? this.fieldId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      points: points ?? this.points,
      waypointTimings: waypointTimings ?? this.waypointTimings,
      pathData: pathData ?? this.pathData,
      canMirror: canMirror ?? this.canMirror,
      mirrorRotations: mirrorRotations ?? this.mirrorRotations,
      matches: matches ?? this.matches,
      selectedMatchId: selectedMatchId ?? this.selectedMatchId,
    );
  }

  ObservedAuto sorted() {
    final sortedPoints = [...points]
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    return copyWith(points: sortedPoints);
  }

  factory ObservedAuto.fromJson(Map<String, dynamic> json) {
    final pointsJson = (json['points'] as List<dynamic>? ?? const [])
        .map((point) => Map<String, dynamic>.from(point as Map))
        .toList();
    final points = pointsJson.map(ObservedAutoPoint.fromJson).toList();
    final waypointTimings =
        (json['waypointTimings'] as List<dynamic>? ?? const [])
            .map((timing) => ObservedWaypointTiming.fromJson(
                Map<String, dynamic>.from(timing as Map)))
            .toList();
    final matches = (json['matches'] as List<dynamic>? ?? const [])
        .map((match) => ObservedMatchObservation.fromJson(
            Map<String, dynamic>.from(match as Map)))
        .toList();

    return ObservedAuto(
      storageId: json['storageId'] as String? ?? '',
      team: json['team'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Auto',
      fieldId: json['fieldId'] as String? ??
          ObservedFieldSpec.officialFields.last.id,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      points: points,
      waypointTimings: waypointTimings,
      pathData: json['path'] == null
          ? null
          : Map<String, dynamic>.from(json['path'] as Map),
      canMirror: json['canMirror'] as bool? ?? false,
      mirrorRotations: _normalizedMirrorRotations(
        (json['mirrorRotations'] as List<dynamic>? ?? const [])
            .map((value) => (value as num?)?.toInt())
            .whereType<int>()
            .toList(),
      ),
      matches: matches,
      selectedMatchId: json['selectedMatchId'] as String?,
    ).sorted();
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 3,
      'storageId': storageId,
      'team': team,
      'name': name,
      'fieldId': fieldId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'points': [for (final point in sorted().points) point.toJson()],
      'waypointTimings': [
        for (final timing in waypointTimings) timing.toJson(),
      ],
      'path': pathData,
      'canMirror': canMirror,
      'mirrorRotations': _normalizedMirrorRotations(mirrorRotations),
      'matches': [
        for (final match in effectiveMatches()) match.toJson(),
      ],
      'selectedMatchId': effectiveSelectedMatchId,
    };
  }

  List<ObservedMatchObservation> effectiveMatches() {
    if (matches.isEmpty) {
      return [
        ObservedMatchObservation(
          id: defaultMatchId,
          matchNumber: 'Match 1',
          label: 'Match 1',
          waypointTimings: waypointTimings.isNotEmpty
              ? waypointTimings
              : const [
                  ObservedWaypointTiming(timeSeconds: 0),
                  ObservedWaypointTiming(timeSeconds: 1.5),
                ],
          markerTimings: [
            for (final point in points)
              ObservedMarkerTiming(
                markerId: point.id,
                timeSeconds: point.timeSeconds,
              ),
          ],
        ).normalizedFor(
          waypointCount:
              waypointTimings.isNotEmpty ? waypointTimings.length : 2,
          markers: points,
          fallbackWaypointTimings: waypointTimings.isNotEmpty
              ? waypointTimings
              : const [
                  ObservedWaypointTiming(timeSeconds: 0),
                  ObservedWaypointTiming(timeSeconds: 1.5),
                ],
        ),
      ];
    }

    return [
      for (final match in matches)
        match.normalizedFor(
          waypointCount: waypointTimings.length,
          markers: points,
          fallbackWaypointTimings: waypointTimings,
        ),
    ];
  }

  String get effectiveSelectedMatchId {
    final available = effectiveMatches();
    final selected = selectedMatchId;
    if (selected != null && available.any((match) => match.id == selected)) {
      return selected;
    }
    return available.first.id;
  }

  ObservedMatchObservation matchById(String? matchId) {
    final available = effectiveMatches();
    return available.firstWhere(
      (match) => match.id == (matchId ?? effectiveSelectedMatchId),
      orElse: () => available.first,
    );
  }

  ObservedAuto viewForMatch(String? matchId) {
    final match = matchById(matchId);
    final markerTimes = {
      for (final timing in match.markerTimings) timing.markerId: timing,
    };
    return copyWith(
      points: [
        for (final point in points)
          point.copyWith(
            timeSeconds:
                markerTimes[point.id]?.timeSeconds ?? point.timeSeconds,
            isToCenter: markerTimes[point.id]?.isToCenter ?? false,
            passNumber: markerTimes[point.id]?.passNumber,
          ),
      ],
      waypointTimings: match.waypointTimings,
      matches: effectiveMatches(),
      selectedMatchId: match.id,
    ).sorted();
  }

  ObservedAuto applyMatchView({
    required String matchId,
    required ObservedAuto editedMatchView,
  }) {
    final structureChanged = _structureSignature() !=
        copyWith(
          pathData: editedMatchView.pathData,
          points: editedMatchView.points,
        )._structureSignature();

    final normalizedMatches = <ObservedMatchObservation>[];
    for (final match in effectiveMatches()) {
      if (match.id == matchId) {
        normalizedMatches.add(
          match.copyWith(
            waypointTimings: editedMatchView.waypointTimings,
            markerTimings: [
              for (final point in editedMatchView.points)
                ObservedMarkerTiming(
                  markerId: point.id,
                  timeSeconds: point.timeSeconds,
                  isToCenter: point.isToCenter,
                  passNumber: point.passNumber,
                ),
            ],
          ).normalizedFor(
            waypointCount: editedMatchView.waypointTimings.length,
            markers: editedMatchView.points,
            fallbackWaypointTimings: editedMatchView.waypointTimings,
          ),
        );
      } else if (structureChanged) {
        normalizedMatches.add(
          match.normalizedFor(
            waypointCount: editedMatchView.waypointTimings.length,
            markers: editedMatchView.points,
            fallbackWaypointTimings: editedMatchView.waypointTimings,
          ),
        );
      } else {
        normalizedMatches.add(match);
      }
    }

    return copyWith(
      name: editedMatchView.name,
      fieldId: editedMatchView.fieldId,
      pathData: editedMatchView.pathData,
      points: editedMatchView.points,
      waypointTimings: editedMatchView.waypointTimings,
      matches: normalizedMatches,
      selectedMatchId: matchId,
    ).sorted();
  }

  double get durationSeconds {
    final lastWaypointTime =
        waypointTimings.isEmpty ? 0 : waypointTimings.last.timeSeconds;
    final lastMarkerTime =
        points.isEmpty ? 0 : sorted().points.last.timeSeconds;
    return (lastWaypointTime > lastMarkerTime
            ? lastWaypointTime
            : lastMarkerTime)
        .toDouble();
  }

  String _structureSignature() {
    return jsonEncode({
      'path': pathData,
      'points': [
        for (final point in points)
          {
            'id': point.id,
            'position': point.position.toJson(),
            'waypointRelativePos': point.waypointRelativePos,
            'note': point.note,
          },
      ],
      'waypointCount': waypointTimings.length,
    });
  }
}

List<double?> _normalizePassTimes(List<double?> values) {
  return List<double?>.generate(
    4,
    (index) => index < values.length ? values[index] : null,
    growable: false,
  );
}

List<int> _normalizedMirrorRotations(List<int> values) {
  final allowed = {0, 90, 180, 270};
  final seen = <int>{};
  final normalized = <int>[];
  for (final value in values) {
    if (allowed.contains(value) && seen.add(value)) {
      normalized.add(value);
    }
  }
  normalized.sort();
  return normalized;
}
