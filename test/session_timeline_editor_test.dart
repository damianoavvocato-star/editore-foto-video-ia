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


  testWidgets('selected clip exposes color controls and persists exposure', (tester) async {
    EditorProject? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 760,
          child: SessionTimelineEditor(
            project: project,
            languageCode: 'en',
            onProjectChanged: (value) => changed = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample').first);
    await tester.pumpAndSettle();
    expect(find.text('Color grading'), findsOneWidget);
    await tester.tap(find.text('Color grading'));
    await tester.pumpAndSettle();
    expect(find.text('Exposure'), findsOneWidget);
    expect(find.text('Contrast'), findsOneWidget);
    final exposureSlider = find.byType(Slider).at(1);
    await tester.ensureVisible(exposureSlider);
    await tester.pumpAndSettle();
    await tester.drag(exposureSlider, const Offset(35, 0));
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(changed!.tracks.single.clips.single.colorGrade.exposure, greaterThan(0));
  });

  testWidgets('selected clip can add and remove animation keyframes', (tester) async {
    EditorProject? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 760,
          child: SessionTimelineEditor(
            project: project,
            languageCode: 'en',
            onProjectChanged: (value) => changed = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Animation & keyframes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add / update at playhead'));
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(changed!.tracks.single.clips.single.keyframes, hasLength(1));
    expect(changed!.tracks.single.clips.single.keyframes.single.property, KeyframeProperty.scale);
    await tester.tap(find.byType(InputChip).first);
    await tester.pumpAndSettle();
    expect(changed!.tracks.single.clips.single.keyframes, isEmpty);
  });

  testWidgets('timeline controls follow the selected Arabic language', (tester) async {
    await showEditor(tester, 'ar');
    expect(find.text('تراجع'), findsOneWidget);
    expect(find.text('إعادة'), findsOneWidget);
    expect(find.text('تكرار'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
    expect(find.text('الخط الزمني'), findsOneWidget);
  });

  testWidgets('ripple delete closes the gap on the selected track', (tester) async {
    const rippleProject = EditorProject(
      id: 'ripple',
      name: 'Ripple edit',
      tracks: [
        EditorTrack(
          id: 'video',
          name: 'Video',
          kind: MediaKind.video,
          clips: [
            EditorClip(
              id: 'first', source: 'first.mp4', kind: MediaKind.video,
              startMs: 0, durationMs: 2000, title: 'First',
            ),
            EditorClip(
              id: 'second', source: 'second.mp4', kind: MediaKind.video,
              startMs: 5000, durationMs: 1000, title: 'Second',
            ),
          ],
        ),
      ],
    );
    EditorProject? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 760,
          child: SessionTimelineEditor(
            project: rippleProject,
            languageCode: 'en',
            onProjectChanged: (value) => changed = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete and close gap'));
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(changed!.tracks.single.clips, hasLength(1));
    expect(changed!.tracks.single.clips.single.id, 'second');
    expect(changed!.tracks.single.clips.single.startMs, 3000);
  });

}