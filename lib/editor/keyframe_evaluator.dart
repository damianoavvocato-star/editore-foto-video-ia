import '../models/editor_project.dart';

/// Deterministic linear evaluation of clip-local keyframes.
/// Returns null when a property has no keyframes; values are held outside
/// the keyed range and linearly interpolated between adjacent points.
class KeyframeEvaluator {
  const KeyframeEvaluator();

  double? valueAt({
    required List<EditorKeyframe> keyframes,
    required KeyframeProperty property,
    required int timeMs,
  }) {
    if (timeMs < 0) throw ArgumentError.value(timeMs, 'timeMs', 'Must be non-negative');
    final points = keyframes.where((point) => point.property == property).toList()
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    if (points.isEmpty) return null;

    // For duplicate timestamps, the last point in the supplied list wins.
    final unique = <EditorKeyframe>[];
    for (final point in points) {
      if (unique.isNotEmpty && unique.last.timeMs == point.timeMs) {
        unique[unique.length - 1] = point;
      } else {
        unique.add(point);
      }
    }
    if (timeMs <= unique.first.timeMs) return unique.first.value;
    if (timeMs >= unique.last.timeMs) return unique.last.value;

    for (var index = 1; index < unique.length; index++) {
      final right = unique[index];
      if (timeMs > right.timeMs) continue;
      final left = unique[index - 1];
      final progress = (timeMs - left.timeMs) / (right.timeMs - left.timeMs);
      return left.value + (right.value - left.value) * progress;
    }
    return unique.last.value;
  }
}
