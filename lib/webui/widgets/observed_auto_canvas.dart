import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/webui/models/observed_auto.dart';
import 'package:pathplanner/webui/models/observed_field.dart';
import 'package:pathplanner/webui/models/observed_path_math.dart';

class ObservedAutoCanvas extends StatefulWidget {
  final ObservedAuto auto;
  final ObservedFieldSpec field;
  final String? selectedPointId;
  final double previewTime;
  final ValueChanged<String?> onPointSelected;
  final ValueChanged<Translation2d> onPointAdded;
  final void Function(String pointId, Translation2d position) onPointMoved;

  const ObservedAutoCanvas({
    required this.auto,
    required this.field,
    required this.selectedPointId,
    required this.previewTime,
    required this.onPointSelected,
    required this.onPointAdded,
    required this.onPointMoved,
    super.key,
  });

  @override
  State<ObservedAutoCanvas> createState() => _ObservedAutoCanvasState();
}

class _ObservedAutoCanvasState extends State<ObservedAutoCanvas> {
  static const _pointHitRadiusPx = 16.0;
  String? _draggingPointId;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.75,
      maxScale: 5,
      boundaryMargin: const EdgeInsets.all(80),
      child: SizedBox(
        width: 1100,
        child: AspectRatio(
          aspectRatio: widget.field.aspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final space = _FieldCoordinateSpace(
                field: widget.field,
                canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
              );

              return GestureDetector(
                onTapDown: (details) {
                  final hit = _findPointAt(details.localPosition, space);
                  widget.onPointSelected(hit?.id);
                },
                onDoubleTapDown: (details) {
                  final hit = _findPointAt(details.localPosition, space);
                  if (hit == null) {
                    widget.onPointAdded(space.toField(details.localPosition));
                  }
                },
                onPanStart: (details) {
                  final hit = _findPointAt(details.localPosition, space);
                  _draggingPointId = hit?.id;
                  if (hit != null) {
                    widget.onPointSelected(hit.id);
                  }
                },
                onPanUpdate: (details) {
                  if (_draggingPointId == null) {
                    return;
                  }
                  widget.onPointMoved(
                    _draggingPointId!,
                    space.toField(details.localPosition),
                  );
                },
                onPanEnd: (_) {
                  _draggingPointId = null;
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        child: Image.asset(
                          widget.field.assetPath,
                          fit: BoxFit.fill,
                        ),
                      ),
                      CustomPaint(
                        painter: _ObservedAutoPainter(
                          context: context,
                          auto: widget.auto,
                          field: widget.field,
                          space: space,
                          selectedPointId: widget.selectedPointId,
                          previewTime: widget.previewTime,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  ObservedAutoPoint? _findPointAt(
    Offset position,
    _FieldCoordinateSpace space,
  ) {
    ObservedAutoPoint? hit;
    double bestDistance = double.infinity;

    for (final point in widget.auto.sorted().points) {
      final pixelPoint = space.toCanvas(point.position);
      final distance = (position - pixelPoint).distance;
      if (distance <= _pointHitRadiusPx && distance < bestDistance) {
        hit = point;
        bestDistance = distance;
      }
    }

    return hit;
  }
}

class _ObservedAutoPainter extends CustomPainter {
  final BuildContext context;
  final ObservedAuto auto;
  final ObservedFieldSpec field;
  final _FieldCoordinateSpace space;
  final String? selectedPointId;
  final double previewTime;

  _ObservedAutoPainter({
    required this.context,
    required this.auto,
    required this.field,
    required this.space,
    required this.selectedPointId,
    required this.previewTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scheme = Theme.of(context).colorScheme;

    _paintGrid(canvas, scheme);
    _paintPath(canvas, scheme);
    _paintRobot(canvas, scheme);
    _paintPoints(canvas, scheme);
  }

  void _paintGrid(Canvas canvas, ColorScheme scheme) {
    final gridPaint = Paint()
      ..color = scheme.surfaceContainerHighest.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    for (double meter = 0; meter <= field.widthMeters; meter += 1) {
      final x = space.toCanvas(Translation2d(meter, 0)).dx;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, space.canvasSize.height),
        gridPaint,
      );
    }
    for (double meter = 0; meter <= field.heightMeters; meter += 1) {
      final y = space.toCanvas(Translation2d(0, meter)).dy;
      canvas.drawLine(
        Offset(0, y),
        Offset(space.canvasSize.width, y),
        gridPaint,
      );
    }
  }

  void _paintPath(Canvas canvas, ColorScheme scheme) {
    final polyline = ObservedPathMath.buildPolyline(auto);
    if (polyline.isEmpty) {
      return;
    }

    final path = Path();
    final start = space.toCanvas(polyline.first);
    path.moveTo(start.dx, start.dy);
    for (final point in polyline.skip(1)) {
      final offset = space.toCanvas(point);
      path.lineTo(offset.dx, offset.dy);
    }

    final glowPaint = Paint()
      ..color = scheme.primary.withValues(alpha: 0.18)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePaint = Paint()
      ..color = scheme.primary
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);
  }

  void _paintRobot(Canvas canvas, ColorScheme scheme) {
    if (auto.points.isEmpty) {
      return;
    }

    final pose = ObservedPathMath.samplePose(auto, previewTime);
    final center = space.toCanvas(pose.position);
    const robotLengthM = 0.95;
    const robotWidthM = 0.85;
    final robotLengthPx = space.metersToCanvasX(robotLengthM);
    final robotWidthPx = space.metersToCanvasY(robotWidthM);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(pose.heading.radians.toDouble());

    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: robotLengthPx,
      height: robotWidthPx,
    );
    final bodyPaint = Paint()..color = scheme.secondary.withValues(alpha: 0.85);
    final outlinePaint = Paint()
      ..color = scheme.surface
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final nosePaint = Paint()..color = scheme.tertiary;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(12)),
      bodyPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(12)),
      outlinePaint,
    );
    canvas.drawCircle(Offset(robotLengthPx * 0.28, 0), 6, nosePaint);

    canvas.restore();
  }

  void _paintPoints(Canvas canvas, ColorScheme scheme) {
    final points = auto.sorted().points;
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final center = space.toCanvas(point.position);
      final selected = point.id == selectedPointId;
      final fillPaint = Paint()
        ..color = selected ? scheme.tertiary : scheme.secondary;
      final outlinePaint = Paint()
        ..color = scheme.surface
        ..strokeWidth = selected ? 4 : 2
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(center, selected ? 12 : 9, fillPaint);
      canvas.drawCircle(center, selected ? 12 : 9, outlinePaint);

      final timeLabel = '${i + 1}  ${point.timeSeconds.toStringAsFixed(2)}s';
      final textPainter = TextPainter(
        text: TextSpan(
          text: timeLabel,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);

      final labelOffset = Offset(
        min(center.dx + 14, space.canvasSize.width - textPainter.width - 8),
        max(center.dy - 20, 8),
      );
      final labelRect = Rect.fromLTWH(
        labelOffset.dx - 6,
        labelOffset.dy - 3,
        textPainter.width + 12,
        textPainter.height + 6,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(8)),
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
      textPainter.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(covariant _ObservedAutoPainter oldDelegate) {
    return oldDelegate.auto != auto ||
        oldDelegate.selectedPointId != selectedPointId ||
        oldDelegate.previewTime != previewTime ||
        oldDelegate.field != field;
  }
}

class _FieldCoordinateSpace {
  final ObservedFieldSpec field;
  final Size canvasSize;

  const _FieldCoordinateSpace({required this.field, required this.canvasSize});

  Offset toCanvas(Translation2d point) {
    final x = ((point.x + field.marginMeters) / field.totalWidthMeters) *
        canvasSize.width;
    final y = ((point.y + field.marginMeters) / field.totalHeightMeters) *
        canvasSize.height;
    return Offset(x.toDouble(), y.toDouble());
  }

  Translation2d toField(Offset offset) {
    final x = ((offset.dx / canvasSize.width) * field.totalWidthMeters) -
        field.marginMeters;
    final y = ((offset.dy / canvasSize.height) * field.totalHeightMeters) -
        field.marginMeters;
    return Translation2d(
      x.clamp(0, field.widthMeters),
      y.clamp(0, field.heightMeters),
    );
  }

  double metersToCanvasX(double meters) {
    return (meters / field.totalWidthMeters) * canvasSize.width;
  }

  double metersToCanvasY(double meters) {
    return (meters / field.totalHeightMeters) * canvasSize.height;
  }
}
