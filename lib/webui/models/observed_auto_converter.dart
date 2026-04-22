import 'package:file/memory.dart';
import 'package:pathplanner/path/pathplanner_path.dart';
import 'package:pathplanner/path/waypoint.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/webui/models/observed_auto.dart';

class ObservedAutoConverter {
  static const _pathDir = '/observed_paths';

  static PathPlannerPath toEditablePath(ObservedAuto auto) {
    final fs = MemoryFileSystem();

    if (auto.pathData != null) {
      return PathPlannerPath.fromJson(
        Map<String, dynamic>.from(auto.pathData!),
        auto.name,
        _pathDir,
        fs,
      );
    }

    final sortedPoints = [...auto.points]
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    if (sortedPoints.length < 2) {
      return PathPlannerPath.defaultPath(
        pathDir: _pathDir,
        fs: fs,
        name: auto.name,
      );
    }

    final path = PathPlannerPath.defaultPath(
      pathDir: _pathDir,
      fs: fs,
      name: auto.name,
    );
    path.waypoints = _waypointsFromObservedPoints(sortedPoints);
    path.rotationTargets = [];
    path.eventMarkers = [];
    path.constraintZones = [];
    path.pointTowardsZones = [];
    path.generatePathPoints();

    return path;
  }

  static List<ObservedWaypointTiming> normalizedTimings(
    ObservedAuto auto,
    int waypointCount,
  ) {
    final existing = auto.waypointTimings.isNotEmpty
        ? auto.waypointTimings
        : [
            for (final point in [
              ...auto.points
            ]..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds)))
              ObservedWaypointTiming(
                timeSeconds: point.timeSeconds,
                note: point.note,
              ),
          ];

    final timings = <ObservedWaypointTiming>[];
    for (int i = 0; i < waypointCount; i++) {
      if (i < existing.length) {
        timings.add(existing[i]);
      } else if (timings.isEmpty) {
        timings.add(const ObservedWaypointTiming(timeSeconds: 0));
      } else {
        timings.add(
          ObservedWaypointTiming(
            timeSeconds: timings.last.timeSeconds + 1,
          ),
        );
      }
    }

    return timings;
  }

  static ObservedAuto fromEditableState({
    required ObservedAuto base,
    required PathPlannerPath path,
    required List<ObservedWaypointTiming> timings,
    required List<ObservedAutoPoint> markers,
  }) {
    final normalizedTimings = ObservedAutoConverter.normalizedTimings(
      base.copyWith(waypointTimings: timings),
      path.waypoints.length,
    );
    final normalizedMarkers = ObservedAutoConverter.normalizedMarkers(
      path: path,
      markers: markers,
    );

    return base.copyWith(
      points: normalizedMarkers,
      waypointTimings: normalizedTimings,
      pathData: path.toJson(),
    );
  }

  static List<ObservedAutoPoint> markersFromAuto(
    ObservedAuto auto,
    PathPlannerPath path,
  ) {
    if (auto.points.isEmpty) {
      return [];
    }

    final legacyWaypointPoints = auto.pathData != null &&
        auto.points.length == auto.waypointTimings.length &&
        auto.points.every((point) => point.id.startsWith('waypoint_'));

    if (legacyWaypointPoints) {
      return [];
    }

    return normalizedMarkers(path: path, markers: auto.points);
  }

  static List<ObservedAutoPoint> normalizedMarkers({
    required PathPlannerPath path,
    required List<ObservedAutoPoint> markers,
  }) {
    return markers.map((marker) {
      final relativePos =
          marker.waypointRelativePos ?? _projectToPath(path, marker.position);
      final clampedPos =
          relativePos.clamp(0, path.waypoints.length - 1).toDouble();
      return marker.copyWith(
        waypointRelativePos: clampedPos,
        position: path.samplePath(clampedPos),
      );
    }).toList()
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
  }

  static List<Waypoint> _waypointsFromObservedPoints(
    List<ObservedAutoPoint> points,
  ) {
    final waypoints = <Waypoint>[];

    for (int i = 0; i < points.length; i++) {
      final anchor = points[i].position;
      final prevAnchor = i > 0 ? points[i - 1].position : null;
      final nextAnchor = i < points.length - 1 ? points[i + 1].position : null;

      waypoints.add(
        Waypoint(
          anchor: anchor,
          prevControl:
              prevAnchor == null ? null : anchor.interpolate(prevAnchor, 0.33),
          nextControl:
              nextAnchor == null ? null : anchor.interpolate(nextAnchor, 0.33),
        ),
      );
    }

    return waypoints;
  }

  static double _projectToPath(PathPlannerPath path, Translation2d target) {
    if (path.waypoints.length < 2) {
      return 0;
    }

    final maxPos = path.waypoints.length - 1.0;
    final sampleCount = (path.waypoints.length * 140).clamp(200, 800);
    double bestPos = 0;
    double bestDistance = double.infinity;

    for (int i = 0; i <= sampleCount; i++) {
      final pos = maxPos * (i / sampleCount);
      final distance = path.samplePath(pos).getDistance(target).toDouble();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPos = pos;
      }
    }

    return bestPos;
  }
}
