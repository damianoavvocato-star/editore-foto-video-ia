import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/editor/remote_export_panel.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  testWidgets('remote export requires a valid secure server endpoint', (tester) async {
    final messages = <String>[];
    const project = EditorProject(
      id: 'export-project',
      name: 'Prova',
      tracks: [
        EditorTrack(
          id: 'video-track',
          name: 'Video',
          kind: MediaKind.video,
          clips: [
            EditorClip(
              id: 'video-clip',
              source: '/tmp/video.mp4',
              kind: MediaKind.video,
              startMs: 0,
              durationMs: 3000,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RemoteExportPanel(
          project: project,
          onClose: () {},
          onMessage: messages.add,
        ),
      ),
    ));

    expect(find.text('Esporta progetto'), findsOneWidget);
    expect(find.text('Impostazioni esportazione'), findsOneWidget);
    final exportButton = find.text('Avvia esportazione');
    await tester.ensureVisible(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(exportButton);
    await tester.pump();

    expect(
      find.textContaining('Inserisci un indirizzo API HTTPS valido'),
      findsOneWidget,
    );
    expect(messages, isEmpty);
  });


  testWidgets('remote HTTPS export requires the configured server bearer token', (tester) async {
    const project = EditorProject(
      id: 'secure-export-project',
      name: 'Prova',
      tracks: [
        EditorTrack(
          id: 'video-track',
          name: 'Video',
          kind: MediaKind.video,
          clips: [
            EditorClip(
              id: 'video-clip',
              source: '/tmp/video.mp4',
              kind: MediaKind.video,
              startMs: 0,
              durationMs: 3000,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RemoteExportPanel(
          project: project,
          onClose: () {},
          onMessage: (_) {},
        ),
      ),
    ));

    await tester.enterText(
      find.widgetWithText(TextField, 'Indirizzo del server media'),
      'https://api.example.com',
    );
    final exportButton = find.text('Avvia esportazione');
    await tester.ensureVisible(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(exportButton);
    await tester.pump();

    expect(
      find.textContaining('è obbligatorio il token condiviso'),
      findsOneWidget,
    );
  });

  testWidgets('remote export is disabled for an empty project', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RemoteExportPanel(
          project: const EditorProject(id: 'empty', name: 'Vuoto'),
          onClose: () {},
          onMessage: (_) {},
        ),
      ),
    ));

    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Avvia esportazione'),
    );
    expect(button.onPressed, isNull);
  });
}
