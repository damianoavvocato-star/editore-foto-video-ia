import 'dart:convert';
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
      jsonDecode(project.encode()) as Map<String, dynamic>,
    );
    final keyframes = restored.tracks.single.clips.single.keyframes;
    expect(keyframes, hasLength(3));
    expect(keyframes[1].timeMs, 2500);
    expect(keyframes[1].property, KeyframeProperty.scale);
    expect(keyframes[1].value, 1.5);
    expect(keyframes[2].property, KeyframeProperty.opacity);
  });


  test('clip color grade settings survive serialization', () {
    const clip = EditorClip(
      id: 'graded',
      source: 'graded.mp4',
      kind: MediaKind.video,
      startMs: 0,
      durationMs: 4000,
      colorGrade: ClipColorGrade(
        exposure: 1.25,
        contrast: 1.2,
        saturation: 0.8,
        temperature: -12,
        tint: 8,
        highlights: -0.4,
        shadows: 0.3,
      ),
    );
    final restored = EditorClip.fromJson(clip.toJson());
    expect(restored.colorGrade.exposure, 1.25);
    expect(restored.colorGrade.contrast, 1.2);
    expect(restored.colorGrade.saturation, 0.8);
    expect(restored.colorGrade.temperature, -12);
    expect(restored.colorGrade.tint, 8);
    expect(restored.colorGrade.highlights, -0.4);
    expect(restored.colorGrade.shadows, 0.3);
  });

  test('color grade rejects out-of-range and non-finite values', () {
    expect(() => ClipColorGrade.fromJson({'exposure': 6}), throwsFormatException);
    expect(() => ClipColorGrade.fromJson({'saturation': double.nan}), throwsFormatException);
    expect(() => ClipColorGrade.fromJson({'contrast': -0.1}), throwsFormatException);
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
