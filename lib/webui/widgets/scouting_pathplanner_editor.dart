import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pathplanner/path/pathplanner_path.dart';
import 'package:pathplanner/path/waypoint.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/webui/models/observed_auto.dart';
import 'package:pathplanner/webui/models/observed_auto_converter.dart';
import 'package:pathplanner/webui/models/observed_field.dart';

class ScoutingPathplannerEditor extends StatefulWidget {
  final ObservedAuto auto;
  final ValueChanged<ObservedAuto> onChanged;

  const ScoutingPathplannerEditor({
    required this.auto,
    required this.onChanged,
    super.key,
  });

  @override
  State<ScoutingPathplannerEditor> createState() =>
      _ScoutingPathplannerEditorState();
}

class _ScoutingPathplannerEditorState extends State<ScoutingPathplannerEditor> {
  final TransformationController _transformController =
      TransformationController();

  late PathPlannerPath _path;
  late List<ObservedWaypointTiming> _timings;
  late List<ObservedAutoPoint> _markers;
  int? _selectedWaypoint;
  String? _selectedMarkerId;
  double _previewTime = 0;
  Waypoint? _draggedPoint;
  String? _draggedMarkerId;
  bool _isDraggingEntity = false;
  Size _lastViewportSize = Size.zero;

  ObservedFieldSpec get _field => ObservedFieldSpec.byId(widget.auto.fieldId);

  @override
  void initState() {
    super.initState();
    _loadAuto();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ScoutingPathplannerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.auto.storageId != widget.auto.storageId ||
        oldWidget.auto.fieldId != widget.auto.fieldId) {
      _loadAuto();
    }
  }

  void _loadAuto() {
    _path = ObservedAutoConverter.toEditablePath(widget.auto);
    _timings = ObservedAutoConverter.normalizedTimings(
      widget.auto,
      _path.waypoints.length,
    );
    _markers = ObservedAutoConverter.markersFromAuto(widget.auto, _path);
    _selectedWaypoint = _path.waypoints.isEmpty ? null : 0;
    _selectedMarkerId = null;
    _previewTime = _clampPreviewTime(_previewTime);
    _draggedPoint = null;
    _draggedMarkerId = null;
    _isDraggingEntity = false;
    _transformController.value = Matrix4.identity();
  }

  double get _durationSeconds {
    final lastWaypointTime = _timings.isEmpty ? 0.0 : _timings.last.timeSeconds;
    final lastMarkerTime = _markers.isEmpty ? 0.0 : _markers.last.timeSeconds;
    return max(lastWaypointTime, lastMarkerTime);
  }

  double _clampPreviewTime(double value) {
    if (_durationSeconds <= 0) {
      return 0;
    }
    return value.clamp(0, _durationSeconds).toDouble();
  }

  void _emitChanged() {
    _path.name = widget.auto.name;
    _path.generatePathPoints();
    widget.onChanged(
      ObservedAutoConverter.fromEditableState(
        base: widget.auto,
        path: _path,
        timings: _timings,
        markers: _markers,
      ),
    );
  }

  void _setWaypointTime(int index, double value) {
    setState(() {
      _timings[index] = _timings[index].copyWith(timeSeconds: value);
      _previewTime = _clampPreviewTime(value);
    });
    _emitChanged();
  }

  void _setMarkerDetails(
    String markerId, {
    required double timeSeconds,
    required bool isToCenter,
    required int? passNumber,
  }) {
    setState(() {
      _markers = [
        for (final marker in _markers)
          if (marker.id == markerId)
            marker.copyWith(
              timeSeconds: timeSeconds,
              isToCenter: isToCenter,
              passNumber: isToCenter ? passNumber : null,
            )
          else
            marker,
      ]..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
      _previewTime = _clampPreviewTime(timeSeconds);
    });
    _emitChanged();
  }

  void _insertWaypointAt(Translation2d anchor) {
    setState(() {
      if (_selectedWaypoint != null &&
          _selectedWaypoint! >= 0 &&
          _selectedWaypoint! < _path.waypoints.length - 1) {
        _path.insertWaypointAfter(_selectedWaypoint!);
        final insertedIndex = _selectedWaypoint! + 1;
        _path.waypoints[insertedIndex].move(anchor.x, anchor.y);

        final prevTime = _timings[_selectedWaypoint!].timeSeconds;
        final nextTime = _timings[insertedIndex].timeSeconds;
        _timings.insert(
          insertedIndex,
          ObservedWaypointTiming(
            timeSeconds: (prevTime + nextTime) / 2,
          ),
        );
        _selectedWaypoint = insertedIndex;
      } else {
        _path.addWaypoint(anchor);
        final time = _timings.isEmpty ? 0.0 : _timings.last.timeSeconds + 1.0;
        _timings.add(ObservedWaypointTiming(timeSeconds: time));
        _selectedWaypoint = _path.waypoints.length - 1;
      }

      _path.generatePathPoints();
      _markers = ObservedAutoConverter.normalizedMarkers(
        path: _path,
        markers: _markers,
      );
      _previewTime = _clampPreviewTime(_previewTime);
    });
    _emitChanged();
  }

  void _deleteWaypoint(int index) {
    if (_path.waypoints.length <= 2 ||
        index < 0 ||
        index >= _path.waypoints.length) {
      return;
    }

    setState(() {
      final removed = _path.waypoints.removeAt(index);
      if (removed.isStartPoint) {
        _path.waypoints.first.prevControl = null;
      } else if (removed.isEndPoint) {
        _path.waypoints.last.nextControl = null;
      }
      _timings.removeAt(index);
      _selectedWaypoint = _path.waypoints.isEmpty
          ? null
          : min(index, _path.waypoints.length - 1);
      _path.generatePathPoints();
      _markers = ObservedAutoConverter.normalizedMarkers(
        path: _path,
        markers: _markers,
      );
      _previewTime = _clampPreviewTime(_previewTime);
    });
    _emitChanged();
  }

  void _deleteMarker(String markerId) {
    setState(() {
      _markers = _markers.where((marker) => marker.id != markerId).toList();
      if (_selectedMarkerId == markerId) {
        _selectedMarkerId = null;
      }
      _previewTime = _clampPreviewTime(_previewTime);
    });
    _emitChanged();
  }

  Future<void> _promptAddMarker(Translation2d fieldPoint) async {
    final relativePos = _nearestRelativePosOnPath(fieldPoint);
    final defaultTime = _timeForRelativePos(relativePos);
    final result = await _showMarkerDialog(
      title: 'Add Path Timestamp',
      initialValue: defaultTime,
    );

    if (result == null) {
      return;
    }

    final markerId = 'marker_${DateTime.now().microsecondsSinceEpoch}';
    final pathPosition = _path.samplePath(relativePos);

    setState(() {
      _markers = [
        ..._markers,
        ObservedAutoPoint(
          id: markerId,
          position: pathPosition,
          waypointRelativePos: relativePos,
          timeSeconds: result.timeSeconds,
          isToCenter: result.isToCenter,
          passNumber: result.isToCenter ? result.passNumber : null,
        ),
      ]..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
      _selectedMarkerId = markerId;
      _selectedWaypoint = null;
      _previewTime = result.timeSeconds;
    });
    _emitChanged();
  }

  Future<void> _editWaypointTime(int index) async {
    final chosenTime = await _showTimeDialog(
      title: index == 0
          ? 'Edit Start Timestamp'
          : index == _path.waypoints.length - 1
              ? 'Edit End Timestamp'
              : 'Edit Waypoint Timestamp',
      initialValue: _timings[index].timeSeconds,
    );

    if (chosenTime == null) {
      return;
    }

    _setWaypointTime(index, chosenTime);
  }

  Future<void> _editMarkerTime(String markerId) async {
    final marker = _markers.firstWhere((entry) => entry.id == markerId);
    final result = await _showMarkerDialog(
      title: 'Edit Path Timestamp',
      initialValue: marker.timeSeconds,
      initialIsToCenter: marker.isToCenter,
      initialPassNumber: marker.passNumber,
    );

    if (result == null) {
      return;
    }

    _setMarkerDetails(
      markerId,
      timeSeconds: result.timeSeconds,
      isToCenter: result.isToCenter,
      passNumber: result.passNumber,
    );
  }

  Future<double?> _showTimeDialog({
    required String title,
    required double initialValue,
  }) async {
    final controller = TextEditingController(
      text: initialValue.toStringAsFixed(2),
    );

    return showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Timestamp (s)',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            onSubmitted: (_) {
              final value = double.tryParse(controller.text.trim());
              if (value != null) {
                Navigator.of(context).pop(value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value != null) {
                  Navigator.of(context).pop(value);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).then((value) {
      controller.dispose();
      return value;
    });
  }

  Future<_MarkerDialogResult?> _showMarkerDialog({
    required String title,
    required double initialValue,
    bool initialIsToCenter = false,
    int? initialPassNumber,
  }) async {
    final controller = TextEditingController(
      text: initialValue.toStringAsFixed(2),
    );
    var isToCenter = initialIsToCenter;
    var passNumber = initialPassNumber ?? 1;

    return showDialog<_MarkerDialogResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Timestamp (s)',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isToCenter,
                    title: const Text('This to center'),
                    onChanged: (value) {
                      setModalState(() {
                        isToCenter = value ?? false;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: passNumber,
                    decoration: const InputDecoration(
                      labelText: 'Pass to center',
                      prefixIcon: Icon(Icons.swap_horiz_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Pass 1')),
                      DropdownMenuItem(value: 2, child: Text('Pass 2')),
                      DropdownMenuItem(value: 3, child: Text('Pass 3')),
                      DropdownMenuItem(value: 4, child: Text('Pass 4')),
                    ],
                    onChanged: isToCenter
                        ? (value) {
                            if (value != null) {
                              setModalState(() {
                                passNumber = value;
                              });
                            }
                          }
                        : null,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = double.tryParse(controller.text.trim());
                    if (value != null) {
                      Navigator.of(context).pop(
                        _MarkerDialogResult(
                          timeSeconds: value,
                          isToCenter: isToCenter,
                          passNumber: isToCenter ? passNumber : null,
                        ),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    ).then((value) {
      controller.dispose();
      return value;
    });
  }

  double _relativePosForPreviewTime() {
    final markersAtTime = _markers.where(
      (marker) => (marker.timeSeconds - _previewTime).abs() < 1e-6,
    );
    if (markersAtTime.isNotEmpty) {
      return markersAtTime.first.waypointRelativePos ?? 0;
    }

    if (_timings.length < 2) {
      return 0;
    }

    if (_previewTime <= _timings.first.timeSeconds) {
      return 0;
    }
    if (_previewTime >= _timings.last.timeSeconds) {
      return (_path.waypoints.length - 1).toDouble();
    }

    for (int i = 0; i < _timings.length - 1; i++) {
      final start = _timings[i].timeSeconds;
      final end = _timings[i + 1].timeSeconds;
      if (_previewTime >= start && _previewTime <= end) {
        final duration = end - start;
        final t = duration <= 0 ? 0.0 : (_previewTime - start) / duration;
        return i + t;
      }
    }

    return (_path.waypoints.length - 1).toDouble();
  }

  double _timeForRelativePos(double relativePos) {
    if (_timings.isEmpty) {
      return 0;
    }
    if (_timings.length == 1) {
      return _timings.first.timeSeconds;
    }

    final clamped = relativePos.clamp(0, _path.waypoints.length - 1).toDouble();
    final index = clamped.floor();
    if (index >= _timings.length - 1) {
      return _timings.last.timeSeconds;
    }

    final t = clamped - index;
    final start = _timings[index].timeSeconds;
    final end = _timings[index + 1].timeSeconds;
    return start + ((end - start) * t);
  }

  void _moveMarkerToFieldPosition(String markerId, Translation2d fieldPoint) {
    final relativePos = _nearestRelativePosOnPath(fieldPoint);
    final pathPosition = _path.samplePath(relativePos);

    setState(() {
      _markers = [
        for (final marker in _markers)
          if (marker.id == markerId)
            marker.copyWith(
              waypointRelativePos: relativePos,
              position: pathPosition,
            )
          else
            marker,
      ];
      for (final marker in _markers) {
        if (marker.id == markerId) {
          _previewTime = _clampPreviewTime(marker.timeSeconds);
          break;
        }
      }
    });
  }

  double _nearestRelativePosOnPath(Translation2d fieldPoint) {
    if (_path.waypoints.length < 2) {
      return 0;
    }

    final maxPos = _path.waypoints.length - 1.0;
    final sampleCount = (_path.waypoints.length * 140).clamp(220, 900);
    double bestPos = 0;
    double bestDistance = double.infinity;

    for (int i = 0; i <= sampleCount; i++) {
      final pos = maxPos * (i / sampleCount);
      final distance = _path.samplePath(pos).getDistance(fieldPoint).toDouble();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPos = pos;
      }
    }

    return bestPos;
  }

  void _zoomBy(double factor) {
    if (_lastViewportSize == Size.zero) {
      return;
    }

    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(1.0, 6.0);
    final normalizedFactor = nextScale / currentScale;
    if ((normalizedFactor - 1).abs() < 1e-6) {
      return;
    }

    final center = _lastViewportSize.center(Offset.zero);
    final matrix = _transformController.value.clone();
    matrix.translateByDouble(center.dx, center.dy, 0, 1);
    matrix.scaleByDouble(normalizedFactor, normalizedFactor, 1, 1);
    matrix.translateByDouble(-center.dx, -center.dy, 0, 1);
    _transformController.value = matrix;
  }

  void _handlePointerDown(
    PointerDownEvent event,
    _ObservedFieldSpace space,
  ) {
    if (event.buttons != kPrimaryMouseButton) {
      return;
    }

    final markerId = _hitTestMarker(event.localPosition, space);
    if (markerId != null) {
      setState(() {
        _selectedMarkerId = markerId;
        _selectedWaypoint = null;
        _draggedMarkerId = markerId;
        _isDraggingEntity = true;
      });
      return;
    }

    final index = _hitTestWaypoint(event.localPosition, space);
    if (index != null) {
      final waypoint = _path.waypoints[index];
      final fieldPoint = space.toField(event.localPosition);
      final started = waypoint.startDragging(
        fieldPoint.x,
        fieldPoint.y,
        space.pixelsToMeters(16),
        space.pixelsToMeters(13),
      );

      setState(() {
        _selectedWaypoint = index;
        _selectedMarkerId = null;
        if (started) {
          _draggedPoint = waypoint;
          _isDraggingEntity = true;
        }
      });
    }
  }

  void _handlePointerMove(
    PointerMoveEvent event,
    _ObservedFieldSpace space,
  ) {
    if (_draggedMarkerId != null) {
      _moveMarkerToFieldPosition(
        _draggedMarkerId!,
        space.toField(event.localPosition),
      );
      return;
    }

    if (_draggedPoint == null) {
      return;
    }

    final fieldPoint = space.toField(event.localPosition);
    setState(() {
      _draggedPoint!.dragUpdate(fieldPoint.x, fieldPoint.y);
      _path.generatePathPoints();
      _markers = ObservedAutoConverter.normalizedMarkers(
        path: _path,
        markers: _markers,
      );
    });
  }

  void _handlePointerEnd() {
    if (_draggedMarkerId != null) {
      setState(() {
        _draggedMarkerId = null;
        _isDraggingEntity = false;
      });
      _emitChanged();
      return;
    }

    if (_draggedPoint == null) {
      if (_isDraggingEntity) {
        setState(() {
          _isDraggingEntity = false;
        });
      }
      return;
    }

    setState(() {
      _draggedPoint!.stopDragging();
      _draggedPoint = null;
      _isDraggingEntity = false;
    });
    _emitChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Editor',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Zoom out',
                  onPressed: () => _zoomBy(0.85),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: 'Reset view',
                  onPressed: () {
                    _transformController.value = Matrix4.identity();
                  },
                  icon: const Icon(Icons.center_focus_strong_rounded),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  onPressed: () => _zoomBy(1.15),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _field.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final canvasSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      _lastViewportSize = canvasSize;
                      final space = _ObservedFieldSpace(
                        field: _field,
                        canvasSize: canvasSize,
                      );

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 1,
                          maxScale: 6,
                          boundaryMargin:
                              EdgeInsets.all(canvasSize.longestSide * 0.9),
                          panEnabled: !_isDraggingEntity,
                          scaleEnabled: !_isDraggingEntity,
                          child: SizedBox(
                            width: canvasSize.width,
                            height: canvasSize.height,
                            child: Listener(
                              onPointerDown: (event) =>
                                  _handlePointerDown(event, space),
                              onPointerMove: (event) =>
                                  _handlePointerMove(event, space),
                              onPointerUp: (_) => _handlePointerEnd(),
                              onPointerCancel: (_) => _handlePointerEnd(),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (details) {
                                  final markerId = _hitTestMarker(
                                    details.localPosition,
                                    space,
                                  );
                                  if (markerId != null) {
                                    setState(() {
                                      _selectedMarkerId = markerId;
                                      _selectedWaypoint = null;
                                      _previewTime = _markers
                                          .firstWhere(
                                              (marker) => marker.id == markerId)
                                          .timeSeconds;
                                    });
                                    return;
                                  }

                                  final waypoint = _hitTestWaypoint(
                                    details.localPosition,
                                    space,
                                  );
                                  setState(() {
                                    _selectedWaypoint = waypoint;
                                    _selectedMarkerId = null;
                                    if (waypoint != null) {
                                      _previewTime =
                                          _timings[waypoint].timeSeconds;
                                    }
                                  });
                                },
                                onDoubleTapDown: (details) async {
                                  final markerId = _hitTestMarker(
                                    details.localPosition,
                                    space,
                                  );
                                  if (markerId != null) {
                                    await _editMarkerTime(markerId);
                                    return;
                                  }

                                  final waypoint = _hitTestWaypoint(
                                    details.localPosition,
                                    space,
                                  );
                                  if (waypoint != null) {
                                    await _editWaypointTime(waypoint);
                                    return;
                                  }

                                  _insertWaypointAt(
                                    space.toField(details.localPosition),
                                  );
                                },
                                onSecondaryTapDown: (details) async {
                                  final markerId = _hitTestMarker(
                                    details.localPosition,
                                    space,
                                  );
                                  if (markerId != null) {
                                    _deleteMarker(markerId);
                                    return;
                                  }

                                  final waypoint = _hitTestWaypoint(
                                    details.localPosition,
                                    space,
                                  );
                                  if (waypoint != null) {
                                    _deleteWaypoint(waypoint);
                                    return;
                                  }

                                  await _promptAddMarker(
                                    space.toField(details.localPosition),
                                  );
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(
                                      _field.assetPath,
                                      fit: BoxFit.contain,
                                    ),
                                    CustomPaint(
                                      painter: _ObservedPathPlannerPainter(
                                        context: context,
                                        path: _path,
                                        timings: _timings,
                                        markers: _markers,
                                        selectedWaypoint: _selectedWaypoint,
                                        selectedMarkerId: _selectedMarkerId,
                                        previewTime: _previewTime,
                                        field: _field,
                                        relativePreviewPos:
                                            _relativePosForPreviewTime(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int? _hitTestWaypoint(Offset position, _ObservedFieldSpace space) {
    int? hitIndex;
    double bestDistance = double.infinity;

    for (int i = _path.waypoints.length - 1; i >= 0; i--) {
      final waypoint = _path.waypoints[i];
      final anchorDistance =
          (position - space.toCanvas(waypoint.anchor)).distance;
      if (anchorDistance <= 18 && anchorDistance < bestDistance) {
        hitIndex = i;
        bestDistance = anchorDistance;
      }

      if (waypoint.prevControl != null) {
        final distance =
            (position - space.toCanvas(waypoint.prevControl!)).distance;
        if (distance <= 14 && distance < bestDistance) {
          hitIndex = i;
          bestDistance = distance;
        }
      }

      if (waypoint.nextControl != null) {
        final distance =
            (position - space.toCanvas(waypoint.nextControl!)).distance;
        if (distance <= 14 && distance < bestDistance) {
          hitIndex = i;
          bestDistance = distance;
        }
      }
    }

    return hitIndex;
  }

  String? _hitTestMarker(Offset position, _ObservedFieldSpace space) {
    String? hitId;
    double bestDistance = double.infinity;

    for (final marker in _markers) {
      final distance = (position - space.toCanvas(marker.position)).distance;
      if (distance <= 14 && distance < bestDistance) {
        hitId = marker.id;
        bestDistance = distance;
      }
    }

    return hitId;
  }
}

class _ObservedFieldSpace {
  final ObservedFieldSpec field;
  final Size canvasSize;

  const _ObservedFieldSpace({
    required this.field,
    required this.canvasSize,
  });

  Offset toCanvas(Translation2d point) {
    final x = ((point.x + field.marginMeters) / field.totalWidthMeters) *
        canvasSize.width;
    final y = canvasSize.height -
        (((point.y + field.marginMeters) / field.totalHeightMeters) *
            canvasSize.height);
    return Offset(x.toDouble(), y.toDouble());
  }

  Translation2d toField(Offset offset) {
    final x = ((offset.dx / canvasSize.width) * field.totalWidthMeters) -
        field.marginMeters;
    final y = (((canvasSize.height - offset.dy) / canvasSize.height) *
            field.totalHeightMeters) -
        field.marginMeters;

    return Translation2d(
      x.clamp(0, field.widthMeters),
      y.clamp(0, field.heightMeters),
    );
  }

  double pixelsToMeters(double pixels) {
    return (pixels / canvasSize.width) * field.totalWidthMeters;
  }

  double metersToPixelsX(double meters) {
    return (meters / field.totalWidthMeters) * canvasSize.width;
  }

  double metersToPixelsY(double meters) {
    return (meters / field.totalHeightMeters) * canvasSize.height;
  }
}

class _ObservedPathPlannerPainter extends CustomPainter {
  final BuildContext context;
  final PathPlannerPath path;
  final List<ObservedWaypointTiming> timings;
  final List<ObservedAutoPoint> markers;
  final int? selectedWaypoint;
  final String? selectedMarkerId;
  final double previewTime;
  final double relativePreviewPos;
  final ObservedFieldSpec field;

  _ObservedPathPlannerPainter({
    required this.context,
    required this.path,
    required this.timings,
    required this.markers,
    required this.selectedWaypoint,
    required this.selectedMarkerId,
    required this.previewTime,
    required this.relativePreviewPos,
    required this.field,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scheme = Theme.of(context).colorScheme;
    final space = _ObservedFieldSpace(field: field, canvasSize: size);

    _paintGrid(canvas, scheme, space);
    _paintControlLines(canvas, scheme, space);
    _paintPath(canvas, scheme, space);
    _paintWaypoints(canvas, scheme, space);
    _paintMarkers(canvas, scheme, space);
    _paintRobotPreview(canvas, scheme, space);
  }

  void _paintGrid(
    Canvas canvas,
    ColorScheme scheme,
    _ObservedFieldSpace space,
  ) {
    final paint = Paint()
      ..color = scheme.surfaceContainerHighest.withValues(alpha: 0.32)
      ..strokeWidth = 1;

    for (double x = 0; x <= field.widthMeters; x += 1) {
      final start = space.toCanvas(Translation2d(x, 0));
      final end = space.toCanvas(Translation2d(x, field.heightMeters));
      canvas.drawLine(start, end, paint);
    }

    for (double y = 0; y <= field.heightMeters; y += 1) {
      final start = space.toCanvas(Translation2d(0, y));
      final end = space.toCanvas(Translation2d(field.widthMeters, y));
      canvas.drawLine(start, end, paint);
    }
  }

  void _paintControlLines(
    Canvas canvas,
    ColorScheme scheme,
    _ObservedFieldSpace space,
  ) {
    final linePaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.55)
      ..strokeWidth = 2;

    for (int i = 0; i < path.waypoints.length; i++) {
      final waypoint = path.waypoints[i];
      final anchor = space.toCanvas(waypoint.anchor);

      if (waypoint.prevControl != null) {
        final prev = space.toCanvas(waypoint.prevControl!);
        canvas.drawLine(anchor, prev, linePaint);
      }
      if (waypoint.nextControl != null) {
        final next = space.toCanvas(waypoint.nextControl!);
        canvas.drawLine(anchor, next, linePaint);
      }
    }
  }

  void _paintPath(
    Canvas canvas,
    ColorScheme scheme,
    _ObservedFieldSpace space,
  ) {
    if (path.pathPoints.isEmpty) {
      return;
    }

    final polyline = path.pathPositions;
    final drawPath = Path();
    final first = space.toCanvas(polyline.first);
    drawPath.moveTo(first.dx, first.dy);

    for (final position in polyline.skip(1)) {
      final offset = space.toCanvas(position);
      drawPath.lineTo(offset.dx, offset.dy);
    }

    canvas.drawPath(
      drawPath,
      Paint()
        ..color = scheme.primary.withValues(alpha: 0.18)
        ..strokeWidth = 12
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      drawPath,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintWaypoints(
    Canvas canvas,
    ColorScheme scheme,
    _ObservedFieldSpace space,
  ) {
    for (int i = 0; i < path.waypoints.length; i++) {
      final waypoint = path.waypoints[i];
      final anchor = space.toCanvas(waypoint.anchor);
      final selected = selectedWaypoint == i;
      final isStart = i == 0;
      final isEnd = i == path.waypoints.length - 1;

      if (waypoint.prevControl != null) {
        _paintControlPoint(
          canvas,
          space.toCanvas(waypoint.prevControl!),
          scheme.surfaceContainerHighest,
          scheme.surface,
        );
      }
      if (waypoint.nextControl != null) {
        _paintControlPoint(
          canvas,
          space.toCanvas(waypoint.nextControl!),
          scheme.surfaceContainerHighest,
          scheme.surface,
        );
      }

      final fill = isStart
          ? scheme.secondary
          : isEnd
              ? scheme.tertiary
              : selected
                  ? scheme.tertiary
                  : scheme.primary;

      canvas.drawCircle(
        anchor,
        selected ? 14 : 11,
        Paint()..color = fill,
      );
      canvas.drawCircle(
        anchor,
        selected ? 14 : 11,
        Paint()
          ..color = scheme.surface
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );

      if (i < timings.length) {
        _paintLabel(
          canvas,
          Offset(anchor.dx + 14, anchor.dy - 28),
          '${timings[i].timeSeconds.toStringAsFixed(2)}s',
        );
      }
    }
  }

  void _paintMarkers(
    Canvas canvas,
    ColorScheme scheme,
    _ObservedFieldSpace space,
  ) {
    for (final marker in markers) {
      final center = space.toCanvas(marker.position);
      final selected = marker.id == selectedMarkerId;
      final size = selected ? 12.0 : 9.0;

      final diamond = Path()
        ..moveTo(center.dx, center.dy - size)
        ..lineTo(center.dx + size, center.dy)
        ..lineTo(center.dx, center.dy + size)
        ..lineTo(center.dx - size, center.dy)
        ..close();

      canvas.drawPath(
        diamond,
        Paint()..color = scheme.secondary,
      );
      canvas.drawPath(
        diamond,
        Paint()
          ..color = scheme.surface
          ..strokeWidth = selected ? 3 : 2
          ..style = PaintingStyle.stroke,
      );

      _paintLabel(
        canvas,
        Offset(center.dx + 12, center.dy + 10),
        '${marker.timeSeconds.toStringAsFixed(2)}s',
      );
    }
  }

  void _paintControlPoint(
    Canvas canvas,
    Offset center,
    Color fill,
    Color stroke,
  ) {
    canvas.drawCircle(center, 8, Paint()..color = fill);
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..color = stroke
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintLabel(Canvas canvas, Offset position, String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromLTWH(
      position.dx - 6,
      position.dy - 4,
      textPainter.width + 12,
      textPainter.height + 8,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    textPainter.paint(canvas, Offset(position.dx, position.dy));
  }

  void _paintRobotPreview(
    Canvas canvas,
    ColorScheme scheme,
    _ObservedFieldSpace space,
  ) {
    if (path.waypoints.isEmpty) {
      return;
    }

    final position = path.samplePath(relativePreviewPos);
    final before = path.samplePath(max(0, relativePreviewPos - 0.02));
    final after = path.samplePath(
      min(path.waypoints.length - 1.0, relativePreviewPos + 0.02),
    );
    final heading = (after - before).norm < 1e-6
        ? path.waypoints.first.heading
        : (after - before).angle;

    final center = space.toCanvas(position);
    final robotLength = space.metersToPixelsX(0.95);
    final robotWidth = space.metersToPixelsY(0.85);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading.radians.toDouble());

    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: robotLength,
      height: robotWidth,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(12)),
      Paint()..color = scheme.secondary.withValues(alpha: 0.85),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(12)),
      Paint()
        ..color = scheme.surface
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(
      Offset(robotLength * 0.28, 0),
      6,
      Paint()..color = scheme.tertiary,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ObservedPathPlannerPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.selectedWaypoint != selectedWaypoint ||
        oldDelegate.selectedMarkerId != selectedMarkerId ||
        oldDelegate.previewTime != previewTime ||
        oldDelegate.timings != timings ||
        oldDelegate.markers != markers ||
        oldDelegate.field != field;
  }
}

class _MarkerDialogResult {
  final double timeSeconds;
  final bool isToCenter;
  final int? passNumber;

  const _MarkerDialogResult({
    required this.timeSeconds,
    required this.isToCenter,
    required this.passNumber,
  });
}
