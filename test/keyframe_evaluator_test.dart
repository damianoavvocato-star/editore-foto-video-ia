import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/editor/keyframe_evaluator.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  const evaluator = KeyframeEvaluator();

  test('interpolates linearly and holds endpoint values', () {
    const points = [
      EditorKeyframe(timeMs: 100, property: KeyframeProperty.scale, value: 1),
      EditorKeyframe(timeMs: 300, property: KeyframeProperty.scale, value: 3),
      EditorKeyframe(timeMs: 200, property: KeyframeProperty.opacity, value: 0.5),
    ];
    expect(evaluator.valueAt(keyframes: points, property: KeyframeProperty.scale, timeMs: 0), 1);
    expect(evaluator.valueAt(keyframes: points, property: KeyframeProperty.scale, timeMs: 200), 2);
    expect(evaluator.valueAt(keyframes: points, property: KeyframeProperty.scale, timeMs: 500), 3);
  });

  test('returns null for an unkeyed property and last duplicate timestamp wins', () {
    const points = [
      EditorKeyframe(timeMs: 100, property: KeyframeProperty.rotation, value: 10),
      EditorKeyframe(timeMs: 100, property: KeyframeProperty.rotation, value: 25),
    ];
    expect(evaluator.valueAt(keyframes: points, property: KeyframeProperty.opacity, timeMs: 100), isNull);
    expect(evaluator.valueAt(keyframes: points, property: KeyframeProperty.rotation, timeMs: 100), 25);
  });

  test('rejects negative evaluation time', () {
    expect(() => evaluator.valueAt(
      keyframes: const [], property: KeyframeProperty.scale, timeMs: -1,
    ), throwsArgumentError);
  });
}
