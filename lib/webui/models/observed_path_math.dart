import 'dart:math';

import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/webui/models/observed_auto.dart';

class ObservedPoseSample {
  final Translation2d position;
  final Rotation2d heading;

  const ObservedPoseSample({required this.position, required this.heading});
}

class ObservedPathMath {
  static List<ObservedAutoPoint> _sortedPoints(ObservedAuto auto) {
    return auto.sorted().points;
  }

  static Translation2d samplePosition(ObservedAuto auto, double timeSeconds) {
    final points = _sortedPoints(auto);
    if (points.isEmpty) {
      return const Translation2d();
    }
    if (points.length == 1) {
      return points.first.position;
    }

    if (timeSeconds <= points.first.timeSeconds) {
      return points.first.position;
    }
    if (timeSeconds >= points.last.timeSeconds) {
      return points.last.position;
    }

    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (timeSeconds >= start.timeSeconds && timeSeconds <= end.timeSeconds) {
        final duration = end.timeSeconds - start.timeSeconds;
        final t =
            duration <= 0 ? 0.0 : (timeSeconds - start.timeSeconds) / duration;
        final p0 = i == 0 ? start.position : points[i - 1].position;
        final p1 = start.position;
        final p2 = end.position;
        final p3 =
            i + 2 >= points.length ? end.position : points[i + 2].position;
        return Translation2d(
          _catmullRom(p0.x, p1.x, p2.x, p3.x, t),
          _catmullRom(p0.y, p1.y, p2.y, p3.y, t),
        );
      }
    }

    return points.last.position;
  }

  static ObservedPoseSample samplePose(ObservedAuto auto, double timeSeconds) {
    final position = samplePosition(auto, timeSeconds);
    final points = _sortedPoints(auto);
    if (points.length < 2) {
      return ObservedPoseSample(
          position: position, heading: const Rotation2d());
    }

    final minTime = points.first.timeSeconds;
    final maxTime = points.last.timeSeconds;
    final beforeTime = max(minTime, timeSeconds - 0.05);
    final afterTime = min(maxTime, timeSeconds + 0.05);

    Translation2d before = samplePosition(auto, beforeTime);
    Translation2d after = samplePosition(auto, afterTime);
    Translation2d delta = after - before;
    if (delta.norm < 1e-6) {
      delta = points.last.position - points.first.position;
    }

    return ObservedPoseSample(position: position, heading: delta.angle);
  }

  static List<Translation2d> buildPolyline(
    ObservedAuto auto, {
    int samplesPerSegment = 24,
  }) {
    final points = _sortedPoints(auto);
    if (points.length <= 1) {
      return points.map((point) => point.position).toList();
    }

    final samples = <Translation2d>[];
    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final duration = end.timeSeconds - start.timeSeconds;
      final sampleCount = duration <= 0 ? 2 : samplesPerSegment;
      for (int step = 0; step < sampleCount; step++) {
        final t = step / sampleCount;
        final sampleTime = start.timeSeconds + (duration * t);
        samples.add(samplePosition(auto, sampleTime));
      }
    }
    samples.add(points.last.position);
    return samples;
  }

  static double _catmullRom(num p0, num p1, num p2, num p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    return 0.5 *
        ((2 * p1) +
            (-p0 + p2) * t +
            ((2 * p0) - (5 * p1) + (4 * p2) - p3) * t2 +
            (-p0 + (3 * p1) - (3 * p2) + p3) * t3);
  }
}
