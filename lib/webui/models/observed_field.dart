import 'dart:ui';

class ObservedFieldSpec {
  final String id;
  final String label;
  final String assetPath;
  final Size imageSize;
  final double pixelsPerMeter;
  final double marginMeters;

  const ObservedFieldSpec({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.imageSize,
    required this.pixelsPerMeter,
    this.marginMeters = 0,
  });

  double get widthMeters =>
      (imageSize.width / pixelsPerMeter) - (marginMeters * 2);

  double get heightMeters =>
      (imageSize.height / pixelsPerMeter) - (marginMeters * 2);

  double get totalWidthMeters => widthMeters + (marginMeters * 2);

  double get totalHeightMeters => heightMeters + (marginMeters * 2);

  double get aspectRatio => imageSize.width / imageSize.height;

  static const List<ObservedFieldSpec> officialFields = [
    ObservedFieldSpec(
      id: 'rapid-react',
      label: 'Rapid React',
      assetPath: 'images/field22.png',
      imageSize: Size(3240, 1620),
      pixelsPerMeter: 196.85,
    ),
    ObservedFieldSpec(
      id: 'charged-up',
      label: 'Charged Up',
      assetPath: 'images/field23.png',
      imageSize: Size(3256, 1578),
      pixelsPerMeter: 196.85,
    ),
    ObservedFieldSpec(
      id: 'crescendo',
      label: 'Crescendo',
      assetPath: 'images/field24.png',
      imageSize: Size(3256, 1616),
      pixelsPerMeter: 196.85,
    ),
    ObservedFieldSpec(
      id: 'reefscape',
      label: 'Reefscape',
      assetPath: 'images/field25.png',
      imageSize: Size(3510, 1610),
      pixelsPerMeter: 200,
    ),
    ObservedFieldSpec(
      id: 'reefscape-annotated',
      label: 'Reefscape (Annotated)',
      assetPath: 'images/field25-annotated.png',
      imageSize: Size(3510, 1610),
      pixelsPerMeter: 200,
    ),
    ObservedFieldSpec(
      id: 'rebuilt',
      label: 'Rebuilt',
      assetPath: 'images/field26.png',
      imageSize: Size(3508, 1814),
      pixelsPerMeter: 200,
      marginMeters: 0.5,
    ),
  ];

  static ObservedFieldSpec byId(String? id) {
    return officialFields.firstWhere(
      (field) => field.id == id,
      orElse: () => officialFields.last,
    );
  }
}
