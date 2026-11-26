import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:editore_foto_video_ia/team/team_studio_screen.dart';

void main() {
  testWidgets('TeamStudio explains missing API configuration', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: TeamStudioScreen(apiBaseUrl: ''),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TeamStudio'), findsOneWidget);
    expect(
      find.text('Configura MEDIA_API_URL per collegare TeamStudio.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
