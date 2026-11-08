import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:editore_foto_video_ia/editor/magiciaedit_panel.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  testWidgets('MagicIAedit uses the protected account session, not a manual token field',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MagicIAeditPanel(
            project: const EditorProject(id: 'test-project', name: 'Test'),
            onProjectChanged: (_) async => true,
            onMessage: (_) {},
            onImportMedia: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Token di accesso del server (facoltativo)'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Indirizzo del server MagicIAedit'),
      400,
    );
    await tester.pumpAndSettle();
    expect(find.text('Indirizzo del server MagicIAedit'), findsOneWidget);
  });
}
