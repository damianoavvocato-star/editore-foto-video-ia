import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:editore_foto_video_ia/editor/magiciaedit_panel.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  testWidgets('MagicIAedit does not expose a manually editable access token',
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
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText ==
                'Token di accesso del server (facoltativo)',
      ),
      findsNothing,
    );
  });
}
