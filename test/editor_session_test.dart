import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';
import 'package:editore_foto_video_ia/state/editor_session.dart';

void main() {
  const project = EditorProject(
    id: 'session',
    name: 'Session',
    tracks: [
      EditorTrack(
        id: 'track',
        name: 'Video',
        kind: MediaKind.video,
        clips: [
          EditorClip(
            id: 'clip',
            source: 'movie.mp4',
            kind: MediaKind.video,
            startMs: 0,
            durationMs: 5000,
            sourceStartMs: 1200,
          ),
        ],
      ),
    ],
  );

  test('session supports select, split and undo redo', () {
    final session = EditorSession(project);
    session.selectClip(project.tracks.single.clips.single);
    session.setPlayhead(2500);
    session.splitSelected();
    expect(session.project.tracks.single.clips, hasLength(2));
    expect(session.project.tracks.single.clips.first.sourceStartMs, 1200);
    expect(session.project.tracks.single.clips.last.sourceStartMs, 3700);
    expect(session.canUndo, isTrue);
    session.undo();
    expect(session.project.tracks.single.clips, hasLength(1));
    session.redo();
    expect(session.project.tracks.single.clips, hasLength(2));
    session.dispose();
  });
}
