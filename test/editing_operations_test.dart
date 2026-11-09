import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/editor/editing_operations.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  const operations = EditingOperations();

  EditorProject sample() => const EditorProject(
        id: 'p1',
        name: 'Test project',
        fps: 30,
        tracks: [
          EditorTrack(
            id: 'v1',
            name: 'Video 1',
            kind: MediaKind.video,
            clips: [
              EditorClip(
                id: 'c1',
                source: '/sample.mp4',
                kind: MediaKind.video,
                startMs: 1000,
                durationMs: 5000,
                sourceStartMs: 1500,
                title: 'Sample',
              ),
            ],
          ),
        ],
      );

  test('move clip clamps negative start to zero', () {
    final result = operations.moveClip(
      project: sample(),
      trackId: 'v1',
      clipId: 'c1',
      newStartMs: -500,
    );
    expect(result.tracks.first.clips.first.startMs, 0);
  });

  test('move clip keeps its end inside safe timeline bounds', () {
    const maxTimelineMs = (1 << 31) - 1;
    final result = operations.moveClip(
      project: sample(), trackId: 'v1', clipId: 'c1',
      newStartMs: maxTimelineMs,
    );
    final clip = result.tracks.first.clips.first;
    expect(clip.startMs, maxTimelineMs - clip.durationMs);
    expect(clip.endMs, maxTimelineMs);
  });

  test('split creates two clips at requested position', () {
    final result = operations.splitClip(
      project: sample(),
      trackId: 'v1',
      clipId: 'c1',
      splitAtMs: 3500,
      newClipId: 'c2',
    );
    expect(result.tracks.first.clips, hasLength(2));
    expect(result.tracks.first.clips[0].durationMs, 2500);
    expect(result.tracks.first.clips[1].startMs, 3500);
    expect(result.tracks.first.clips[1].durationMs, 2500);
    expect(result.tracks.first.clips[0].sourceStartMs, 1500);
    expect(result.tracks.first.clips[1].sourceStartMs, 4000);
  });

  test('split and duplicate preserve clip effects and remap keyframe time', () {
    const effected = EditorClip(
      id: 'effected', source: '/effected.mp4', kind: MediaKind.video,
      startMs: 0, durationMs: 4000,
      colorGrade: ClipColorGrade(exposure: 1.5),
      keyframes: [
        EditorKeyframe(timeMs: 500, property: KeyframeProperty.scale, value: 1),
        EditorKeyframe(timeMs: 2500, property: KeyframeProperty.scale, value: 2),
      ],
    );
    final base = EditorProject(id: 'effects', name: 'Effects', tracks: [
      const EditorTrack(id: 'v1', name: 'Video', kind: MediaKind.video, clips: [effected]),
    ]);
    final split = operations.splitClip(
      project: base, trackId: 'v1', clipId: 'effected',
      splitAtMs: 2000, newClipId: 'second',
    );
    final first = split.tracks.first.clips.first;
    final second = split.tracks.first.clips.last;
    expect(first.keyframes.map((point) => point.timeMs), [500]);
    expect(second.keyframes.single.timeMs, 500);
    expect(second.keyframes.single.value, 2);
    expect(second.colorGrade.exposure, 1.5);

    final duplicated = operations.duplicateClip(
      project: base, trackId: 'v1', clipId: 'effected', newClipId: 'copy',
    );
    expect(duplicated.tracks.first.clips.last.keyframes, effected.keyframes);
    expect(duplicated.tracks.first.clips.last.colorGrade.exposure, 1.5);
  });

  test('split refuses a duplicate clip ID', () {
    final result = operations.splitClip(
      project: sample(),
      trackId: 'v1',
      clipId: 'c1',
      splitAtMs: 3500,
      newClipId: 'c1',
    );
    expect(result.tracks.first.clips, hasLength(1));
    expect(result.tracks.first.clips.single.id, 'c1');
  });


  test('split refuses an ID already used on another track', () {
    final base = sample();
    final secondTrack = const EditorTrack(
      id: 'a1', name: 'Audio', kind: MediaKind.audio,
      clips: [EditorClip(
        id: 'taken', source: '/audio.mp3', kind: MediaKind.audio,
        startMs: 0, durationMs: 1000,
      )],
    );
    final project = EditorProject(
      id: base.id, name: base.name, width: base.width, height: base.height,
      fps: base.fps, tracks: [...base.tracks, secondTrack],
    );
    final result = operations.splitClip(
      project: project, trackId: 'v1', clipId: 'c1',
      splitAtMs: 3500, newClipId: 'taken',
    );
    expect(result.tracks.first.clips, hasLength(1));
  });

  test('trim enforces at least one frame', () {
    final result = operations.trimClip(
      project: sample(),
      trackId: 'v1',
      clipId: 'c1',
      durationMs: 0,
    );
    expect(result.tracks.first.clips.first.durationMs, 34);
  });

  test('trim falls back to a standard frame rate for invalid project fps', () {
    final base = sample();
    final project = EditorProject(
      id: base.id, name: base.name, width: base.width, height: base.height,
      fps: 0, tracks: base.tracks,
    );
    final result = operations.trimClip(
      project: project, trackId: 'v1', clipId: 'c1', durationMs: 0,
    );
    expect(result.tracks.first.clips.first.durationMs, 34);
  });

  test('trim clamps oversized duration and start to safe timeline bounds', () {
    const maxTimelineMs = (1 << 31) - 1;
    final result = operations.trimClip(
      project: sample(), trackId: 'v1', clipId: 'c1',
      durationMs: maxTimelineMs + 5000,
      newStartMs: maxTimelineMs,
    );
    final clip = result.tracks.first.clips.first;
    expect(clip.durationMs, maxTimelineMs);
    expect(clip.startMs, 0);
    expect(clip.endMs, maxTimelineMs);
  });

  test('trim clamps negative duration to one frame', () {
    final result = operations.trimClip(
      project: sample(), trackId: 'v1', clipId: 'c1', durationMs: -500,
    );
    expect(result.tracks.first.clips.first.durationMs, 34);
  });

  test('transition settings are stored on the outgoing clip', () {
    final result = operations.setTransitionAfter(
      project: sample(), trackId: 'v1', clipId: 'c1',
      durationMs: 450, type: 'wipeleft',
    );
    final clip = result.tracks.first.clips.first;
    expect(clip.transitionAfterMs, 450);
    expect(clip.transitionAfter, 'wipeleft');
  });

  test('duplicate clip receives a new ID and offset', () {
    final result = operations.duplicateClip(
      project: sample(), trackId: 'v1', clipId: 'c1',
      newClipId: 'c2', offsetMs: 6000,
    );
    expect(result.tracks.first.clips, hasLength(2));
    expect(result.tracks.first.clips.last.id, 'c2');
    expect(result.tracks.first.clips.last.startMs, 7000);
    expect(result.tracks.first.clips.last.sourceStartMs, 1500);
  });

  test('duplicate clip clamps its end to safe timeline bounds', () {
    const maxTimelineMs = (1 << 31) - 1;
    final result = operations.duplicateClip(
      project: sample(), trackId: 'v1', clipId: 'c1',
      newClipId: 'c2', offsetMs: maxTimelineMs,
    );
    final duplicate = result.tracks.first.clips.last;
    expect(duplicate.startMs, maxTimelineMs - duplicate.durationMs);
    expect(duplicate.endMs, maxTimelineMs);
  });

  test('delete clip with ripple shifts following clips left', () {
    final project = sample();
    final withNext = operations.addClip(
      project: project,
      trackId: 'v1',
      clip: const EditorClip(
        id: 'c2', source: '/next.mp4', kind: MediaKind.video,
        startMs: 7000, durationMs: 2000,
      ),
    );
    final result = operations.deleteClip(
      project: withNext, trackId: 'v1', clipId: 'c1', ripple: true,
    );
    expect(result.tracks.first.clips, hasLength(1));
    expect(result.tracks.first.clips.single.id, 'c2');
    expect(result.tracks.first.clips.single.startMs, 2000);
  });

  test('add clip keeps timeline ordered and ignores duplicate IDs', () {
    final project = sample();
    final added = operations.addClip(
      project: project, trackId: 'v1',
      clip: const EditorClip(
        id: 'c2', source: '/early.mp4', kind: MediaKind.video,
        startMs: 0, durationMs: 1000,
      ),
    );
    expect(added.tracks.first.clips.first.id, 'c2');
    final duplicate = operations.addClip(
      project: added, trackId: 'v1', clip: added.tracks.first.clips.first,
    );
    expect(duplicate.tracks.first.clips, hasLength(2));
  });

  test('clip speed is clamped to supported playback range', () {
    final slow = operations.setClipSpeed(
      project: sample(), trackId: 'v1', clipId: 'c1', speed: 0.1,
    );
    expect(slow.tracks.first.clips.first.speed, 0.25);
    final fast = operations.setClipSpeed(
      project: sample(), trackId: 'v1', clipId: 'c1', speed: 8,
    );
    expect(fast.tracks.first.clips.first.speed, 4.0);
  });

  test('non-finite clip speed falls back to normal playback', () {
    final result = operations.setClipSpeed(
      project: sample(), trackId: 'v1', clipId: 'c1', speed: double.nan,
    );
    expect(result.tracks.first.clips.first.speed, 1.0);
  });

  test('locked track cannot change clip speed', () {
    final locked = sample().tracks.first.copyWith(locked: true);
    final project = EditorProject(id: 'p1', name: 'Test', tracks: [locked]);
    final result = operations.setClipSpeed(
      project: project, trackId: 'v1', clipId: 'c1', speed: 2.0,
    );
    expect(result.tracks.first.clips.first.speed, 1.0);
  });

  test('locked track cannot be moved', () {
    final locked = sample().tracks.first.copyWith(locked: true);
    final project = EditorProject(
      id: 'p1',
      name: 'Test',
      tracks: [locked],
    );
    final result = operations.moveClip(
      project: project,
      trackId: 'v1',
      clipId: 'c1',
      newStartMs: 9000,
    );
    expect(result.tracks.first.clips.first.startMs, 1000);
  });

  test('transition type and duration are constrained to supported values', () {
    final result = operations.setTransitionAfter(
      project: sample(), trackId: 'v1', clipId: 'c1',
      durationMs: 50000, type: 'unsupported',
    );
    final clip = result.tracks.first.clips.first;
    expect(clip.transitionAfter, 'fade');
    expect(clip.transitionAfterMs, 10000);
  });

  test('track mute and lock state can be changed independently', () {
    final muted = operations.setTrackMuted(
      project: sample(), trackId: 'v1', muted: true,
    );
    expect(muted.tracks.first.muted, isTrue);
    expect(muted.tracks.first.clips, sample().tracks.first.clips);

    final locked = operations.setTrackLocked(
      project: muted, trackId: 'v1', locked: true,
    );
    expect(locked.tracks.first.locked, isTrue);
    expect(locked.tracks.first.muted, isTrue);
  });

  test('delete without ripple leaves later clip positions unchanged', () {
    final withNext = operations.addClip(
      project: sample(),
      trackId: 'v1',
      clip: const EditorClip(
        id: 'c2', source: '/next.mp4', kind: MediaKind.video,
        startMs: 7000, durationMs: 2000,
      ),
    );
    final result = operations.deleteClip(
      project: withNext, trackId: 'v1', clipId: 'c1',
    );
    expect(result.tracks.first.clips.single.id, 'c2');
    expect(result.tracks.first.clips.single.startMs, 7000);
  });

  test('color grade and keyframes update only unlocked target clip', () {
    final graded = operations.setClipColorGrade(
      project: sample(), trackId: 'v1', clipId: 'c1',
      colorGrade: const ClipColorGrade(exposure: 1.5, saturation: 1.2),
    );
    expect(graded.tracks.first.clips.first.colorGrade.exposure, 1.5);
    final keyed = operations.setClipKeyframe(
      project: graded, trackId: 'v1', clipId: 'c1',
      keyframe: const EditorKeyframe(timeMs: 1200, property: KeyframeProperty.scale, value: 1.4),
    );
    expect(keyed.tracks.first.clips.first.keyframes.single.value, 1.4);
    final replaced = operations.setClipKeyframe(
      project: keyed, trackId: 'v1', clipId: 'c1',
      keyframe: const EditorKeyframe(timeMs: 1200, property: KeyframeProperty.scale, value: 1.8),
    );
    expect(replaced.tracks.first.clips.first.keyframes, hasLength(1));
    expect(replaced.tracks.first.clips.first.keyframes.single.value, 1.8);
    final removed = operations.removeClipKeyframe(
      project: replaced, trackId: 'v1', clipId: 'c1',
      timeMs: 1200, property: KeyframeProperty.scale,
    );
    expect(removed.tracks.first.clips.first.keyframes, isEmpty);
  });

  test('locked track and out-of-clip keyframe do not change project', () {
    final locked = sample().tracks.first.copyWith(locked: true);
    final lockedProject = EditorProject(id: 'p1', name: 'Locked', tracks: [locked]);
    final lockedResult = operations.setClipColorGrade(
      project: lockedProject, trackId: 'v1', clipId: 'c1',
      colorGrade: const ClipColorGrade(exposure: 2),
    );
    expect(lockedResult.encode(), lockedProject.encode());
    final outOfRange = operations.setClipKeyframe(
      project: sample(), trackId: 'v1', clipId: 'c1',
      keyframe: const EditorKeyframe(timeMs: 5001, property: KeyframeProperty.opacity, value: 0.5),
    );
    expect(outOfRange.tracks.first.clips.first.keyframes, isEmpty);
  });

  test('locked track cannot delete clips', () {
    final lockedTrack = sample().tracks.first.copyWith(locked: true);
    final lockedProject = EditorProject(
      id: 'p1', name: 'Test project', tracks: [lockedTrack],
    );
    final result = operations.deleteClip(
      project: lockedProject, trackId: 'v1', clipId: 'c1',
    );
    expect(result.tracks.first.clips, hasLength(1));
  });
}
