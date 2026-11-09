import '../models/editor_project.dart';

/// Pure editing operations on project metadata. These operations are non-destructive:
/// they update clip timing in the project model; media rendering is a separate phase.
class EditingOperations {
  const EditingOperations();

  EditorProject updateTrack(
    EditorProject project,
    String trackId,
    EditorTrack Function(EditorTrack track) transform,
  ) {
    return EditorProject(
      id: project.id,
      name: project.name,
      width: project.width,
      height: project.height,
      fps: project.fps,
      tracks: project.tracks
          .map((track) => track.id == trackId ? transform(track) : track)
          .toList(),
    );
  }

  EditorProject moveClip({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required int newStartMs,
  }) {
    const maxTimelineMs = (1 << 31) - 1;
    return updateTrack(project, trackId, (track) {
      if (track.locked) return track;
      return track.copyWith(
        clips: track.clips
            .map((clip) => clip.id == clipId
                ? clip.copyWith(startMs: newStartMs.clamp(0, maxTimelineMs - clip.durationMs.clamp(0, maxTimelineMs)).toInt())
                : clip)
            .toList(),
      );
    });
  }

  /// Trim a clip by setting its visible duration and (optionally) its start.
  /// Duration is clamped to at least one frame at the project's frame rate.
  EditorProject trimClip({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required int durationMs,
    int? newStartMs,
  }) {
    // Persisted projects may contain a malformed frame rate. Fall back to a
    // standard rate so trimming cannot throw while calculating one frame.
    final safeFps = project.fps > 0 ? project.fps : 30;
    final minDuration = (1000 / safeFps).ceil().clamp(1, 1000).toInt();
    // Keep clip end timestamps within the signed 32-bit millisecond range;
    // this also avoids overflow in timeline widgets and serializers.
    const maxTimelineMs = (1 << 31) - 1;
    final duration = durationMs.clamp(minDuration, maxTimelineMs).toInt();
    return updateTrack(project, trackId, (track) {
      if (track.locked) return track;
      return track.copyWith(
        clips: track.clips
            .map((clip) => clip.id == clipId
                ? clip.copyWith(
                    durationMs: duration,
                    startMs: newStartMs == null
                        ? clip.startMs
                        : newStartMs.clamp(0, maxTimelineMs - duration).toInt(),
                  )
                : clip)
            .toList(),
      );
    });
  }

  /// Split a clip at an absolute project time. Returns the original project if
  /// the split point is not strictly inside the clip.
  EditorProject splitClip({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required int splitAtMs,
    required String newClipId,
  }) {
    return updateTrack(project, trackId, (track) {
      if (track.locked || project.tracks.any((candidate) => candidate.clips.any((clip) => clip.id == newClipId))) return track;
      final result = <EditorClip>[];
      for (final clip in track.clips) {
        if (clip.id != clipId ||
            splitAtMs <= clip.startMs ||
            splitAtMs >= clip.endMs) {
          result.add(clip);
          continue;
        }
        final firstDuration = splitAtMs - clip.startMs;
        final secondDuration = clip.endMs - splitAtMs;
        result
          ..add(clip.copyWith(durationMs: firstDuration))
          ..add(EditorClip(
            id: newClipId,
            source: clip.source,
            kind: clip.kind,
            startMs: splitAtMs,
            durationMs: secondDuration,
            sourceStartMs: clip.sourceStartMs + firstDuration,
            title: clip.title.isEmpty ? 'Split clip' : '${clip.title} (2)',
            speed: clip.speed,
          ));
      }
      result.sort((a, b) => a.startMs.compareTo(b.startMs));
      return track.copyWith(clips: result);
    });
  }

  /// Sets the transition from this clip to the next clip on the same track.
  EditorProject setTransitionAfter({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required int durationMs,
    String type = 'fade',
  }) {
    const allowed = {
      'fade', 'wipeleft', 'wiperight', 'slideleft', 'slideright',
      'circleopen', 'circleclose', 'dissolve',
    };
    final safeDuration = durationMs.clamp(0, 10000).toInt();
    final safeType = allowed.contains(type) ? type : 'fade';
    return updateTrack(project, trackId, (track) {
      if (track.locked) return track;
      return track.copyWith(clips: track.clips.map((clip) =>
        clip.id == clipId
          ? clip.copyWith(transitionAfterMs: safeDuration, transitionAfter: safeType)
          : clip).toList());
    });
  }

  /// Duplicates a clip with a caller-provided unique ID and optional offset.
  EditorProject duplicateClip({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required String newClipId,
    int offsetMs = 0,
  }) {
    return updateTrack(project, trackId, (track) {
      if (track.locked || project.tracks.any((candidate) => candidate.clips.any((clip) => clip.id == newClipId))) return track;
      EditorClip? source;
      for (final clip in track.clips) {
        if (clip.id == clipId) { source = clip; break; }
      }
      if (source == null) return track;
      const maxTimelineMs = (1 << 31) - 1;
      final safeDuration = source.durationMs.clamp(1, maxTimelineMs).toInt();
      // Clamp the duplicate's start as well as its end: a large positive
      // offset must never create an end timestamp outside the timeline range.
      final requestedStart = source.startMs + offsetMs;
      final safeStart = requestedStart.clamp(0, maxTimelineMs - safeDuration).toInt();
      final duplicate = EditorClip(
        id: newClipId, source: source.source, kind: source.kind,
        startMs: safeStart,
        durationMs: safeDuration,
        sourceStartMs: source.sourceStartMs,
        title: source.title.isEmpty ? 'Copy' : '${source.title} (copy)',
        speed: source.speed, transitionAfterMs: source.transitionAfterMs,
        transitionAfter: source.transitionAfter,
      );
      final clips = [...track.clips, duplicate]..sort((a,b) => a.startMs.compareTo(b.startMs));
      return track.copyWith(clips: clips);
    });
  }


  /// Removes a clip. When [ripple] is true, later clips on the same track
  /// move left by the removed clip duration, preserving their relative gaps.
  EditorProject deleteClip({
    required EditorProject project,
    required String trackId,
    required String clipId,
    bool ripple = false,
  }) {
    return updateTrack(project, trackId, (track) {
      if (track.locked) return track;
      final removed = track.clips.where((clip) => clip.id == clipId).toList();
      if (removed.isEmpty) return track;
      final target = removed.first;
      final clips = track.clips.where((clip) => clip.id != clipId).map((clip) {
        if (ripple && clip.startMs >= target.endMs) {
          return clip.copyWith(startMs: (clip.startMs - target.durationMs).clamp(0, 1 << 31).toInt());
        }
        return clip;
      }).toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
      return track.copyWith(clips: clips);
    });
  }

  /// Inserts a clip into an unlocked track. IDs must be unique within the track.
  EditorProject addClip({
    required EditorProject project,
    required String trackId,
    required EditorClip clip,
  }) {
    return updateTrack(project, trackId, (track) {
      if (track.locked || project.tracks.any((candidate) => candidate.clips.any((existing) => existing.id == clip.id))) {
        return track;
      }
      final clips = [...track.clips, clip]..sort((a, b) => a.startMs.compareTo(b.startMs));
      return track.copyWith(clips: clips);
    });
  }

  /// Persists clip-local color settings without changing source media.
  EditorProject setClipColorGrade({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required ClipColorGrade colorGrade,
  }) => updateTrack(project, trackId, (track) {
    if (track.locked) return track;
    return track.copyWith(clips: track.clips.map((clip) =>
      clip.id == clipId ? clip.copyWith(colorGrade: colorGrade) : clip,
    ).toList());
  });

  /// Adds or replaces one keyframe for the same property and timestamp.
  EditorProject setClipKeyframe({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required EditorKeyframe keyframe,
  }) => updateTrack(project, trackId, (track) {
    if (track.locked) return track;
    return track.copyWith(clips: track.clips.map((clip) {
      if (clip.id != clipId || keyframe.timeMs > clip.durationMs) return clip;
      final points = clip.keyframes.where((point) =>
        point.property != keyframe.property || point.timeMs != keyframe.timeMs,
      ).toList()..add(keyframe);
      points.sort((a, b) {
        final byTime = a.timeMs.compareTo(b.timeMs);
        return byTime != 0 ? byTime : a.property.index.compareTo(b.property.index);
      });
      return clip.copyWith(keyframes: points);
    }).toList());
  });

  EditorProject removeClipKeyframe({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required int timeMs,
    required KeyframeProperty property,
  }) => updateTrack(project, trackId, (track) {
    if (track.locked) return track;
    return track.copyWith(clips: track.clips.map((clip) =>
      clip.id == clipId
        ? clip.copyWith(keyframes: clip.keyframes.where((point) =>
            point.timeMs != timeMs || point.property != property,
          ).toList())
        : clip,
    ).toList());
  });

  /// Changes the mute state of a track without modifying its clips.
  EditorProject setTrackMuted({
    required EditorProject project,
    required String trackId,
    required bool muted,
  }) => updateTrack(project, trackId, (track) => track.copyWith(muted: muted));

  EditorProject setClipSpeed({
    required EditorProject project,
    required String trackId,
    required String clipId,
    required double speed,
  }) {
    // Reject NaN and infinities from malformed project data or UI input.
    // A neutral 1x speed is safer than persisting a non-finite value.
    final safeSpeed = speed.isFinite ? speed.clamp(0.25, 4.0).toDouble() : 1.0;
    return updateTrack(project, trackId, (track) {
      if (track.locked) return track;
      return track.copyWith(
        clips: track.clips
            .map((clip) => clip.id == clipId ? clip.copyWith(speed: safeSpeed) : clip)
            .toList(),
      );
    });
  }

  EditorProject setTrackLocked({
    required EditorProject project,
    required String trackId,
    required bool locked,
  }) =>
      updateTrack(project, trackId, (track) => track.copyWith(locked: locked));
}
