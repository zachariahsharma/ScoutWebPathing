import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/webui/models/observed_auto.dart';
import 'package:pathplanner/webui/models/observed_path_math.dart';

void main() {
  test('ObservedAuto sorts points by time when loading', () {
    final auto = ObservedAuto.fromJson({
      'storageId': 'test-auto',
      'team': '254',
      'name': 'Amp Side',
      'fieldId': 'rebuilt',
      'createdAt': '2026-04-21T00:00:00.000Z',
      'updatedAt': '2026-04-21T00:00:00.000Z',
      'points': [
        {
          'id': 'b',
          'position': {'x': 3.0, 'y': 2.0},
          'timeSeconds': 2.0,
          'note': 'score',
        },
        {
          'id': 'a',
          'position': {'x': 1.0, 'y': 2.0},
          'timeSeconds': 0.0,
          'note': 'start',
        },
      ],
    });

    expect(auto.points.first.id, 'a');
    expect(auto.points.last.id, 'b');
  });

  test('ObservedPathMath samples interpolated positions between points', () {
    const auto = ObservedAuto(
      storageId: 'test-auto',
      team: '111',
      name: 'Center',
      fieldId: 'rebuilt',
      createdAt: '2026-04-21T00:00:00.000Z',
      updatedAt: '2026-04-21T00:00:00.000Z',
      points: [
        ObservedAutoPoint(
          id: 'a',
          position: Translation2d(0, 0),
          timeSeconds: 0,
        ),
        ObservedAutoPoint(
          id: 'b',
          position: Translation2d(2, 2),
          timeSeconds: 2,
        ),
        ObservedAutoPoint(
          id: 'c',
          position: Translation2d(4, 0),
          timeSeconds: 4,
        ),
      ],
    );

    final sample = ObservedPathMath.samplePosition(auto, 1.0);

    expect(sample.x, greaterThan(0.5));
    expect(sample.x, lessThan(2.5));
    expect(sample.y, greaterThan(0.5));
  });

  test('ObservedAuto can project a selected match into the editor view', () {
    final auto = ObservedAuto.fromJson({
      'storageId': 'test-auto',
      'team': '111',
      'name': 'Center',
      'fieldId': 'rebuilt',
      'createdAt': '2026-04-21T00:00:00.000Z',
      'updatedAt': '2026-04-21T00:00:00.000Z',
      'points': [
        {
          'id': 'marker_a',
          'position': {'x': 1.0, 'y': 2.0},
          'waypointRelativePos': 0.4,
          'timeSeconds': 0.8,
        },
      ],
      'waypointTimings': [
        {'timeSeconds': 0.0},
        {'timeSeconds': 2.0},
      ],
      'matches': [
        {
          'id': 'match_1',
          'label': 'Q12',
          'waypointTimings': [
            {'timeSeconds': 0.0},
            {'timeSeconds': 1.7},
          ],
          'markerTimings': [
            {'markerId': 'marker_a', 'timeSeconds': 0.6},
          ],
          'passToCenterTimes': [2.1, null, null, null],
        },
      ],
      'selectedMatchId': 'match_1',
    });

    final view = auto.viewForMatch('match_1');

    expect(view.waypointTimings.last.timeSeconds, 1.7);
    expect(view.points.single.timeSeconds, 0.6);
    expect(view.selectedMatchId, 'match_1');
  });

  test('ObservedMatchObservation displayLabel deduplicates identical values',
      () {
    const match = ObservedMatchObservation(
      id: 'match_1',
      matchNumber: 'Match 1',
      label: 'Match 1',
    );

    expect(match.displayLabel, 'Match 1');
  });

  test('ObservedMatchObservation passToCenterTimes reset from marker timings',
      () {
    const match = ObservedMatchObservation(
      id: 'match_1',
      matchNumber: 'Q12',
      label: 'Einstein',
      passToCenterTimes: [2.1, 4.5, null, null],
      markerTimings: [
        ObservedMarkerTiming(
          markerId: 'marker_a',
          timeSeconds: 1.4,
          isToCenter: true,
          passNumber: 1,
        ),
        ObservedMarkerTiming(
          markerId: 'marker_b',
          timeSeconds: 3.2,
          isToCenter: false,
          passNumber: 2,
        ),
      ],
    );

    const markers = [
      ObservedAutoPoint(
        id: 'marker_a',
        position: Translation2d(1, 1),
        timeSeconds: 1.4,
      ),
      ObservedAutoPoint(
        id: 'marker_b',
        position: Translation2d(2, 2),
        timeSeconds: 3.2,
      ),
    ];

    final normalized = match.normalizedFor(
      waypointCount: 2,
      markers: markers,
      fallbackWaypointTimings: const [
        ObservedWaypointTiming(timeSeconds: 0),
        ObservedWaypointTiming(timeSeconds: 2),
      ],
    );

    expect(normalized.passToCenterTimes, [1.4, null, null, null]);
  });
}
