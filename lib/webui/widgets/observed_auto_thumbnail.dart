import 'package:flutter/material.dart';
import 'package:pathplanner/path/pathplanner_path.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/webui/models/observed_auto.dart';
import 'package:pathplanner/webui/models/observed_auto_converter.dart';
import 'package:pathplanner/webui/models/observed_field.dart';

class ObservedAutoThumbnail extends StatelessWidget {
  final ObservedAuto auto;

  const ObservedAutoThumbnail({
    required this.auto,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final field = ObservedFieldSpec.byId(auto.fieldId);
    final previewAuto = auto.viewForMatch(auto.selectedMatchId);
    final path = ObservedAutoConverter.toEditablePath(previewAuto);
    final markers = ObservedAutoConverter.markersFromAuto(previewAuto, path);

    return AspectRatio(
      aspectRatio: field.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              field.assetPath,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
            ),
            CustomPaint(
              painter: _ObservedAutoThumbnailPainter(
                context: context,
                field: field,
                path: path,
                markers: markers,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailFieldSpace {
  final ObservedFieldSpec field;
  final Size canvasSize;

  const _ThumbnailFieldSpace({
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
}

class _ObservedAutoThumbnailPainter extends CustomPainter {
  final BuildContext context;
  final ObservedFieldSpec field;
  final PathPlannerPath path;
  final List<ObservedAutoPoint> markers;

  _ObservedAutoThumbnailPainter({
    required this.context,
    required this.field,
    required this.path,
    required this.markers,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (path.pathPositions.isEmpty) {
      return;
    }

    final scheme = Theme.of(context).colorScheme;
    final space = _ThumbnailFieldSpace(field: field, canvasSize: size);
    final drawPath = Path();
    final first = space.toCanvas(path.pathPositions.first);
    drawPath.moveTo(first.dx, first.dy);

    for (final position in path.pathPositions.skip(1)) {
      final offset = space.toCanvas(position);
      drawPath.lineTo(offset.dx, offset.dy);
    }

    canvas.drawPath(
      drawPath,
      Paint()
        ..color = scheme.primary.withValues(alpha: 0.2)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      drawPath,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (int i = 0; i < path.waypoints.length; i++) {
      final waypoint = path.waypoints[i];
      final isStart = i == 0;
      final isEnd = i == path.waypoints.length - 1;
      final center = space.toCanvas(waypoint.anchor);
      canvas.drawCircle(
        center,
        7,
        Paint()
          ..color = isStart
              ? scheme.secondary
              : isEnd
                  ? scheme.tertiary
                  : scheme.primary,
      );
      canvas.drawCircle(
        center,
        7,
        Paint()
          ..color = scheme.surface
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    for (final marker in markers) {
      final center = space.toCanvas(marker.position);
      final diamond = Path()
        ..moveTo(center.dx, center.dy - 7)
        ..lineTo(center.dx + 7, center.dy)
        ..lineTo(center.dx, center.dy + 7)
        ..lineTo(center.dx - 7, center.dy)
        ..close();

      canvas.drawPath(
        diamond,
        Paint()..color = scheme.secondary,
      );
      canvas.drawPath(
        diamond,
        Paint()
          ..color = scheme.surface
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ObservedAutoThumbnailPainter oldDelegate) {
    return oldDelegate.field != field ||
        oldDelegate.path != path ||
        oldDelegate.markers != markers;
  }
}
