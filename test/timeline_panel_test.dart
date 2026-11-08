import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/editor/timeline_panel.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  testWidgets('timeline shows tracks, ruler and selects a clip', (tester) async {
    EditorClip? selected;
    const clip = EditorClip(
      id: 'clip-1', source: '/tmp/clip.mp4', kind: MediaKind.video,
      startMs: 1000, durationMs: 3000, title: 'Vacanze',
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: TimelinePanel(
        tracks: [
          EditorTrack(id: 'video', name: 'Video', kind: MediaKind.video, clips: [clip]),
          const EditorTrack(id: 'audio', name: 'Audio', kind: MediaKind.audio),
        ],
        playheadMs: 0,
        onClipSelected: (value) => selected = value,
        onPlayheadChanged: (_) {},
      )),
    )));
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Vacanze'), findsOneWidget);
    expect(find.text('Video'), findsWidgets);
    expect(find.text('Audio'), findsWidgets);
    expect(find.text('0s'), findsOneWidget);
    await tester.tap(find.text('Vacanze'));
    expect(selected, same(clip));
  });

  testWidgets('empty timeline explains how to start', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelinePanel(
      tracks: const [], playheadMs: 0,
      onClipSelected: (_) {}, onPlayheadChanged: (_) {},
    ))));
    expect(find.text('Importa foto, video o audio per iniziare la timeline.'), findsOneWidget);
  });
}
