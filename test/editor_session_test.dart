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
          EditorClip(
            id: 'later',
            source: 'later.mp4',
            kind: MediaKind.video,
            startMs: 7000,
            durationMs: 2000,
          ),
        ],
      ),
    ],
  );

  test('session supports select, split and undo redo', () {
    final session = EditorSession(project);
    session.selectClip(project.tracks.single.clips.first);
    session.setPlayhead(2500);
    session.splitSelected();
    expect(session.project.tracks.single.clips, hasLength(3));
    expect(session.project.tracks.single.clips.first.sourceStartMs, 1200);
    expect(session.project.tracks.single.clips[1].sourceStartMs, 3700);
    expect(session.canUndo, isTrue);
    session.undo();
    expect(session.project.tracks.single.clips, hasLength(2));
    session.redo();
    expect(session.project.tracks.single.clips, hasLength(3));
    session.dispose();
  });

  test('duplicate selects the copy and participates in undo redo', () {
    final session = EditorSession(project);
    session.selectClip(project.tracks.single.clips.first);
    session.duplicateSelected();
    expect(session.project.tracks.single.clips, hasLength(3));
    expect(session.selectedClipId, isNot('clip'));
    expect(session.selectedClip?.startMs, 5000);
    session.undo();
    expect(session.project.tracks.single.clips, hasLength(2));
    session.redo();
    expect(session.project.tracks.single.clips, hasLength(3));
    session.dispose();
  });

  test('delete clears selection and undo restores the clip', () {
    final session = EditorSession(project);
    session.selectClip(project.tracks.single.clips.first);
    session.deleteSelected();
    expect(session.project.tracks.single.clips.map((c) => c.id), ['later']);
    expect(session.selectedClip, isNull);
    session.undo();
    expect(session.project.tracks.single.clips, hasLength(2));
    session.dispose();
  });

  test('transition and track mute are undoable; locked track blocks edits', () {
    final session = EditorSession(project);
    session.selectClip(project.tracks.single.clips.first);
    session.setSelectedTransition(type: 'wipeleft', durationMs: 900);
    expect(session.selectedClip?.transitionAfter, 'wipeleft');
    expect(session.selectedClip?.transitionAfterMs, 900);
    session.toggleSelectedTrackMuted();
    expect(session.selectedTrack?.muted, isTrue);
    session.toggleSelectedTrackLocked();
    expect(session.selectedTrack?.locked, isTrue);
    final before = session.project.encode();
    session.trimSelected(1000);
    expect(session.project.encode(), before);
    session.toggleSelectedTrackLocked();
    expect(session.selectedTrack?.locked, isFalse);
    session.undo();
    expect(session.selectedTrack?.locked, isTrue);
    session.dispose();
  });

  test('selected color and keyframe edits participate in undo redo', () {
    final session = EditorSession(project);
    session.selectClip(project.tracks.single.clips.first);
    session.setSelectedColorGrade(const ClipColorGrade(exposure: 1.25));
    session.setSelectedKeyframe(const EditorKeyframe(
      timeMs: 500, property: KeyframeProperty.opacity, value: 0.4,
    ));
    expect(session.selectedClip?.colorGrade.exposure, 1.25);
    expect(session.selectedClip?.keyframes.single.value, 0.4);
    session.undo();
    expect(session.selectedClip?.keyframes, isEmpty);
    session.redo();
    expect(session.selectedClip?.keyframes.single.value, 0.4);
    session.removeSelectedKeyframe(timeMs: 500, property: KeyframeProperty.opacity);
    expect(session.selectedClip?.keyframes, isEmpty);
    session.dispose();
  });

  test('locked track can be unlocked even when its clip is selected', () {
    final lockedProject = project.copyWith(
      tracks: [project.tracks.single.copyWith(locked: true)],
    );
    final session = EditorSession(lockedProject);
    session.selectClip(lockedProject.tracks.single.clips.first);
    session.toggleSelectedTrackLocked();
    expect(session.selectedTrack?.locked, isFalse);
    session.dispose();
  });
}
