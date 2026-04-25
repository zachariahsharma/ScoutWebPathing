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
    final waypointTimes = _timings
        .map((timing) => timing.timeSeconds)
        .whereType<double>()
        .toList();
    final markerTimes = _markers
        .map((marker) => marker.timeSeconds)
        .whereType<double>()
        .toList();
    final lastWaypointTime = waypointTimes.isEmpty ? 0.0 : waypointTimes.last;
    final lastMarkerTime = markerTimes.isEmpty ? 0.0 : markerTimes.last;
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

  void _setWaypointTime(int index, double? value) {
    setState(() {
      _timings[index] = _timings[index].copyWith(timeSeconds: value);
      if (value != null) {
        _previewTime = _clampPreviewTime(value);
      }
    });
    _emitChanged();
  }

  void _setMarkerDetails(
    String markerId, {
    required double? timeSeconds,
    required String name,
    required bool isToCenter,
    required int? passNumber,
  }) {
    setState(() {
      _markers = [
        for (final marker in _markers)
          if (marker.id == markerId)
            marker.copyWith(
              timeSeconds: timeSeconds,
              note: name.trim(),
              isToCenter: isToCenter,
              passNumber: isToCenter ? passNumber : null,
            )
          else
            marker,
      ]..sort(_compareMarkerTimes);
      if (timeSeconds != null) {
        _previewTime = _clampPreviewTime(timeSeconds);
      }
    });
    _emitChanged();
  }

  void _insertWaypointAt(Translation2d anchor) {
    setState(() {
      _path.addWaypoint(anchor);
      _timings.add(const ObservedWaypointTiming());
      _selectedWaypoint = _path.waypoints.length - 1;

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

  void _straightenControlSegment(_WaypointControlHit hit) {
    final index = hit.waypointIndex;
    if (index < 0 || index >= _path.waypoints.length) {
      return;
    }

    setState(() {
      if (hit.side == _WaypointControlSide.prev && index > 0) {
        _path.waypoints[index].prevControl = null;
        _path.waypoints[index - 1].nextControl = null;
      } else if (hit.side == _WaypointControlSide.next &&
          index < _path.waypoints.length - 1) {
        _path.waypoints[index].nextControl = null;
        _path.waypoints[index + 1].prevControl = null;
      }

      _selectedWaypoint = index;
      _selectedMarkerId = null;
      _path.generatePathPoints();
      _markers = ObservedAutoConverter.normalizedMarkers(
        path: _path,
        markers: _markers,
      );
      final time = _timings[index].timeSeconds;
      if (time != null) {
        _previewTime = time;
      }
    });
    _emitChanged();
  }

  bool _restoreControlSegments(int index) {
    if (index < 0 || index >= _path.waypoints.length) {
      return false;
    }

    var restored = false;

    setState(() {
      final waypoint = _path.waypoints[index];
      if (index > 0 && waypoint.prevControl == null) {
        final previous = _path.waypoints[index - 1];
        waypoint.prevControl =
            waypoint.anchor.interpolate(previous.anchor, 1 / 3);
        previous.nextControl ??=
            previous.anchor.interpolate(waypoint.anchor, 1 / 3);
        restored = true;
      }

      if (index < _path.waypoints.length - 1 && waypoint.nextControl == null) {
        final next = _path.waypoints[index + 1];
        waypoint.nextControl = waypoint.anchor.interpolate(next.anchor, 1 / 3);
        next.prevControl ??= next.anchor.interpolate(waypoint.anchor, 1 / 3);
        restored = true;
      }

      if (restored) {
        _selectedWaypoint = index;
        _selectedMarkerId = null;
        _path.generatePathPoints();
        _markers = ObservedAutoConverter.normalizedMarkers(
          path: _path,
          markers: _markers,
        );
        final time = _timings[index].timeSeconds;
        if (time != null) {
          _previewTime = time;
        }
      }
    });

    if (restored) {
      _emitChanged();
    }
    return restored;
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
    final result = await _showMarkerDialog(
      title: 'Add Path Timestamp',
      initialValue: null,
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
          note: result.name,
          isToCenter: result.isToCenter,
          passNumber: result.isToCenter ? result.passNumber : null,
        ),
      ]..sort(_compareMarkerTimes);
      _selectedMarkerId = markerId;
      _selectedWaypoint = null;
      if (result.timeSeconds != null) {
        _previewTime = result.timeSeconds!;
      }
    });
    _emitChanged();
  }

  Future<void> _editWaypointTime(int index) async {
    final result = await _showTimeDialog(
      title: index == 0
          ? 'Edit Start Timestamp'
          : index == _path.waypoints.length - 1
              ? 'Edit End Timestamp'
              : 'Edit Waypoint Timestamp',
      initialValue: _timings[index].timeSeconds,
      canDelete: _path.waypoints.length > 2,
    );

    if (result == null) {
      return;
    }

    switch (result.action) {
      case _WaypointTimeDialogAction.save:
        _setWaypointTime(index, result.timeSeconds);
      case _WaypointTimeDialogAction.delete:
        _deleteWaypoint(index);
    }
  }

  Future<void> _editMarkerTime(String markerId) async {
    final marker = _markers.firstWhere((entry) => entry.id == markerId);
    final result = await _showMarkerDialog(
      title: 'Edit Path Timestamp',
      initialValue: marker.timeSeconds,
      initialName: marker.note,
      initialIsToCenter: marker.isToCenter,
      initialPassNumber: marker.passNumber,
      canDelete: true,
    );

    if (result == null) {
      return;
    }

    switch (result.action) {
      case _MarkerDialogAction.save:
        _setMarkerDetails(
          markerId,
          timeSeconds: result.timeSeconds,
          name: result.name,
          isToCenter: result.isToCenter,
          passNumber: result.passNumber,
        );
      case _MarkerDialogAction.delete:
        _deleteMarker(markerId);
    }
  }

  Future<_WaypointTimeDialogResult?> _showTimeDialog({
    required String title,
    required double? initialValue,
    required bool canDelete,
  }) async {
    final controller = TextEditingController(
      text: initialValue == null ? '' : initialValue.toStringAsFixed(2),
    );

    return showDialog<_WaypointTimeDialogResult>(
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
              hintText: 'N/A',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            onSubmitted: (_) {
              Navigator.of(context).pop(
                _WaypointTimeDialogResult.save(
                  _parseOptionalTime(controller.text),
                ),
              );
            },
          ),
          actions: [
            TextButton.icon(
              onPressed: canDelete
                  ? () => Navigator.of(context).pop(
                        const _WaypointTimeDialogResult.delete(),
                      )
                  : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _WaypointTimeDialogResult.save(
                    _parseOptionalTime(controller.text),
                  ),
                );
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
    required double? initialValue,
    String initialName = '',
    bool initialIsToCenter = false,
    int? initialPassNumber,
    bool canDelete = false,
  }) async {
    final controller = TextEditingController(
      text: initialValue == null ? '' : initialValue.toStringAsFixed(2),
    );
    final nameController = TextEditingController(text: initialName);
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
                      hintText: 'N/A',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.label_outline),
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
                TextButton.icon(
                  onPressed: canDelete
                      ? () => Navigator.of(context).pop(
                            const _MarkerDialogResult.delete(),
                          )
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _MarkerDialogResult(
                        timeSeconds: _parseOptionalTime(controller.text),
                        name: nameController.text.trim(),
                        isToCenter: isToCenter,
                        passNumber: isToCenter ? passNumber : null,
                      ),
                    );
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
      nameController.dispose();
      return value;
    });
  }

  double _relativePosForPreviewTime() {
    final markersAtTime = _markers.where(
      (marker) =>
          marker.timeSeconds != null &&
          (marker.timeSeconds! - _previewTime).abs() < 1e-6,
    );
    if (markersAtTime.isNotEmpty) {
      return markersAtTime.first.waypointRelativePos ?? 0;
    }

    if (_timings.length < 2) {
      return 0;
    }

    final timedTimings = [
      for (int i = 0; i < _timings.length; i++)
        if (_timings[i].timeSeconds != null)
          (index: i, time: _timings[i].timeSeconds!),
    ];
    if (timedTimings.length < 2) {
      return 0;
    }

    if (_previewTime <= timedTimings.first.time) {
      return 0;
    }
    if (_previewTime >= timedTimings.last.time) {
      return (_path.waypoints.length - 1).toDouble();
    }

    for (int i = 0; i < timedTimings.length - 1; i++) {
      final start = timedTimings[i].time;
      final end = timedTimings[i + 1].time;
      if (_previewTime >= start && _previewTime <= end) {
        final duration = end - start;
        final t = duration <= 0 ? 0.0 : (_previewTime - start) / duration;
        return timedTimings[i].index +
            ((timedTimings[i + 1].index - timedTimings[i].index) * t);
      }
    }

    return (_path.waypoints.length - 1).toDouble();
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
      ]..sort(_compareMarkerTimes);
      for (final marker in _markers) {
        if (marker.id == markerId && marker.timeSeconds != null) {
          _previewTime = _clampPreviewTime(marker.timeSeconds!);
          break;
        }
      }
    });
  }

  static double? _parseOptionalTime(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : double.tryParse(trimmed);
  }

  static int _compareMarkerTimes(ObservedAutoPoint a, ObservedAutoPoint b) {
    return _sortTime(a.timeSeconds).compareTo(_sortTime(b.timeSeconds));
  }

  static double _sortTime(double? timeSeconds) {
    return timeSeconds ?? double.infinity;
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
                                    final marker = _markers.firstWhere(
                                      (marker) => marker.id == markerId,
                                    );
                                    setState(() {
                                      _selectedMarkerId = markerId;
                                      _selectedWaypoint = null;
                                      if (marker.timeSeconds != null) {
                                        _previewTime = marker.timeSeconds!;
                                      }
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
                                    final time = waypoint == null
                                        ? null
                                        : _timings[waypoint].timeSeconds;
                                    if (time != null) {
                                      _previewTime = time;
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

                                  final controlHit = _hitTestWaypointControl(
                                    details.localPosition,
                                    space,
                                  );
                                  if (controlHit != null) {
                                    _straightenControlSegment(controlHit);
                                    return;
                                  }

                                  final waypoint = _hitTestWaypoint(
                                    details.localPosition,
                                    space,
                                  );
                                  if (waypoint != null) {
                                    if (_restoreControlSegments(waypoint)) {
                                      return;
                                    }
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

  _WaypointControlHit? _hitTestWaypointControl(
    Offset position,
    _ObservedFieldSpace space,
  ) {
    _WaypointControlHit? hit;
    double bestDistance = double.infinity;

    for (int i = _path.waypoints.length - 1; i >= 0; i--) {
      final waypoint = _path.waypoints[i];
      final anchor = space.toCanvas(waypoint.anchor);
      final anchorDistance = (position - anchor).distance;

      if (waypoint.prevControl != null) {
        final prev = space.toCanvas(waypoint.prevControl!);
        final controlDistance = (position - prev).distance;
        final lineDistance = anchorDistance > 18
            ? _distanceToLineSegment(position, anchor, prev)
            : double.infinity;
        final distance = min(controlDistance, lineDistance);
        if ((controlDistance <= 14 || lineDistance <= 6) &&
            distance < bestDistance) {
          hit = _WaypointControlHit(i, _WaypointControlSide.prev);
          bestDistance = distance;
        }
      }

      if (waypoint.nextControl != null) {
        final next = space.toCanvas(waypoint.nextControl!);
        final controlDistance = (position - next).distance;
        final lineDistance = anchorDistance > 18
            ? _distanceToLineSegment(position, anchor, next)
            : double.infinity;
        final distance = min(controlDistance, lineDistance);
        if ((controlDistance <= 14 || lineDistance <= 6) &&
            distance < bestDistance) {
          hit = _WaypointControlHit(i, _WaypointControlSide.next);
          bestDistance = distance;
        }
      }
    }

    return hit;
  }

  double _distanceToLineSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = segment.distanceSquared;
    if (lengthSquared == 0) {
      return (point - start).distance;
    }

    final t = (((point.dx - start.dx) * segment.dx) +
            ((point.dy - start.dy) * segment.dy)) /
        lengthSquared;
    final clampedT = t.clamp(0.0, 1.0).toDouble();
    final closest = Offset(
      start.dx + (segment.dx * clampedT),
      start.dy + (segment.dy * clampedT),
    );
    return (point - closest).distance;
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

enum _WaypointControlSide { prev, next }

class _WaypointControlHit {
  final int waypointIndex;
  final _WaypointControlSide side;

  const _WaypointControlHit(this.waypointIndex, this.side);
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
        final time = timings[i].timeSeconds;
        _paintLabel(
          canvas,
          Offset(anchor.dx + 14, anchor.dy - 28),
          time == null ? '' : '${time.toStringAsFixed(2)}s',
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
        _markerLabel(marker),
      );
    }
  }

  String _markerLabel(ObservedAutoPoint marker) {
    final name = marker.note.trim();
    final time = marker.timeSeconds;
    if (name.isEmpty) {
      return time == null ? '' : '${time.toStringAsFixed(2)}s';
    }
    return time == null ? name : '$name ${time.toStringAsFixed(2)}s';
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
    if (text.isEmpty) {
      return;
    }

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

enum _MarkerDialogAction { save, delete }

class _MarkerDialogResult {
  final _MarkerDialogAction action;
  final double? timeSeconds;
  final String name;
  final bool isToCenter;
  final int? passNumber;

  const _MarkerDialogResult({
    required this.timeSeconds,
    this.name = '',
    required this.isToCenter,
    required this.passNumber,
  }) : action = _MarkerDialogAction.save;

  const _MarkerDialogResult.delete()
      : action = _MarkerDialogAction.delete,
        timeSeconds = null,
        name = '',
        isToCenter = false,
        passNumber = null;
}

enum _WaypointTimeDialogAction { save, delete }

class _WaypointTimeDialogResult {
  final _WaypointTimeDialogAction action;
  final double? timeSeconds;

  const _WaypointTimeDialogResult._({
    required this.action,
    this.timeSeconds,
  });

  const _WaypointTimeDialogResult.save(double? timeSeconds)
      : this._(
          action: _WaypointTimeDialogAction.save,
          timeSeconds: timeSeconds,
        );

  const _WaypointTimeDialogResult.delete()
      : this._(action: _WaypointTimeDialogAction.delete);
}
