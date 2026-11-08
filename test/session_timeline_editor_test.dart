import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/editor/session_timeline_editor.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  const project = EditorProject(
    id: 'localization',
    name: 'Localization',
    tracks: [
      EditorTrack(
        id: 'video',
        name: 'Video',
        kind: MediaKind.video,
        clips: [
          EditorClip(
            id: 'clip',
            source: 'sample.mp4',
            kind: MediaKind.video,
            startMs: 0,
            durationMs: 4000,
            title: 'Sample',
          ),
        ],
      ),
    ],
  );

  Future<void> showEditor(WidgetTester tester, String languageCode) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: SessionTimelineEditor(
            project: project,
            languageCode: languageCode,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('timeline controls follow the selected English language', (tester) async {
    await showEditor(tester, 'en');
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Redo'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
  });

  testWidgets('timeline controls follow the selected Arabic language', (tester) async {
    await showEditor(tester, 'ar');
    expect(find.text('تراجع'), findsOneWidget);
    expect(find.text('إعادة'), findsOneWidget);
    expect(find.text('تكرار'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
    expect(find.text('الخط الزمني'), findsOneWidget);
  });
}
