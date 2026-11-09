import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  test('clip keyframes survive project encode and decode', () {
    const project = EditorProject(
      id: 'keyframed-project',
      name: 'Keyframes',
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
              startMs: 1000,
              durationMs: 5000,
              keyframes: [
                EditorKeyframe(
                  timeMs: 0,
                  property: KeyframeProperty.scale,
                  value: 1,
                ),
                EditorKeyframe(
                  timeMs: 2500,
                  property: KeyframeProperty.scale,
                  value: 1.5,
                ),
                EditorKeyframe(
                  timeMs: 5000,
                  property: KeyframeProperty.opacity,
                  value: 0.75,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final restored = EditorProject.fromJson(
      project.toJson() as Map<String, dynamic>,
    );
    final keyframes = restored.tracks.single.clips.single.keyframes;
    expect(keyframes, hasLength(3));
    expect(keyframes[1].timeMs, 2500);
    expect(keyframes[1].property, KeyframeProperty.scale);
    expect(keyframes[1].value, 1.5);
    expect(keyframes[2].property, KeyframeProperty.opacity);
  });

  test('legacy clips without keyframes remain readable', () {
    final clip = EditorClip.fromJson({
      'id': 'legacy',
      'source': 'old.mp4',
      'kind': 'video',
      'startMs': 0,
      'durationMs': 1000,
    });
    expect(clip.keyframes, isEmpty);
  });

  test('invalid keyframe data is rejected instead of silently discarded', () {
    expect(
      () => EditorKeyframe.fromJson({
        'timeMs': -1,
        'property': 'scale',
        'value': 1.0,
      }),
      throwsFormatException,
    );
    expect(
      () => EditorKeyframe.fromJson({
        'timeMs': 100,
        'property': 'unknown',
        'value': 1.0,
      }),
      throwsFormatException,
    );
    expect(
      () => EditorKeyframe.fromJson({
        'timeMs': 100,
        'property': 'scale',
        'value': double.infinity,
      }),
      throwsFormatException,
    );
  });
}
