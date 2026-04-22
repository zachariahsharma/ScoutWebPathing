import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/main.dart';

void main() {
  testWidgets('scouting web app renders', (widgetTester) async {
    await widgetTester.binding.setSurfaceSize(const Size(1600, 1000));
    await widgetTester.pumpWidget(const PathPlannerScoutingWebApp());
    await widgetTester.pumpAndSettle();

    expect(find.text('Scouting Autos'), findsOneWidget);
  });
}
