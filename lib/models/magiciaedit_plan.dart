import '../models/editor_project.dart';

const _magicImageExtensions = {'jpg', 'jpeg', 'png', 'webp'};
const _magicVideoExtensions = {'mp4', 'mov', 'avi', 'webm', 'm4v'};
const _magicTransitions = {
  'fade', 'wipeleft', 'wiperight', 'slideleft', 'slideright',
  'circleopen', 'circleclose', 'dissolve',
};

String _boundedString(Object? value, String fallback, int maxLength) {
  final text = (value ?? fallback).toString();
  return text.length <= maxLength ? text : text.substring(0, maxLength);
}

class MagicIAeditPlanClip {
  const MagicIAeditPlanClip({
    required this.assetId,
    required this.sourceStartMs,
    required this.durationMs,
    required this.startMs,
    required this.transitionAfterMs,
    required this.transitionAfter,
    required this.reason,
  });

  final String assetId;
  final int sourceStartMs;
  final int durationMs;
  final int startMs;
  final int transitionAfterMs;
  final String transitionAfter;
  final String reason;

  factory MagicIAeditPlanClip.fromJson(Map<String, dynamic> json) {
    int readInt(String key, {required int fallback}) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is num && value.isFinite) return value.round();
      throw FormatException('Campo MagicIAedit non valido: $key');
    }

    final assetId = json['assetId'];
    if (assetId is! String || assetId.trim().isEmpty) {
      throw const FormatException('La clip MagicIAedit non contiene assetId.');
    }
    final sourceStartMs = readInt('sourceStartMs', fallback: 0);
    final durationMs = readInt('durationMs', fallback: 3000);
    final startMs = readInt('startMs', fallback: 0);
    final transitionAfterMs = readInt('transitionAfterMs', fallback: 0);
    final transitionAfter = (json['transitionAfter'] ?? 'fade').toString().toLowerCase();
    if (sourceStartMs < 0 ||
        sourceStartMs > 86400000 ||
        durationMs < 500 ||
        durationMs > 20000 ||
        startMs < 0 ||
        startMs > 86400000 ||
        transitionAfterMs < 0 ||
        transitionAfterMs > 2000 ||
        transitionAfterMs > durationMs * 0.45 ||
        !_magicTransitions.contains(transitionAfter)) {
      throw const FormatException('La clip MagicIAedit contiene valori fuori limite.');
    }
    return MagicIAeditPlanClip(
      assetId: assetId,
      sourceStartMs: sourceStartMs,
      durationMs: durationMs,
      startMs: startMs,
      transitionAfterMs: transitionAfterMs,
      transitionAfter: transitionAfter,
      reason: _boundedString(json['reason'], '', 240),
    );
  }
}

/// Validated, reviewable AI montage proposal. The source path map is kept
/// client-side and is never sent back to the cloud provider.
class MagicIAeditPlan {
  const MagicIAeditPlan._({
    required this.title,
    required this.description,
    required this.durationMs,
    required this.clips,
    required this.sourcePaths,
  });

  final String title;
  final String description;
  final int durationMs;
  final List<MagicIAeditPlanClip> clips;
  final Map<String, String> sourcePaths;

  factory MagicIAeditPlan.fromResult(Map<String, dynamic> result) {
    final rawClips = result['clips'];
    final rawSources = result['sourcePaths'];
    if (rawClips is! List || rawClips.isEmpty || rawClips.length > 24) {
      throw const FormatException('Il piano MagicIAedit deve contenere da 1 a 24 clip.');
    }
    if (rawSources is! Map) {
      throw const FormatException('Mappatura dei media locali non disponibile.');
    }

    final sources = <String, String>{};
    for (final entry in rawSources.entries) {
      if (entry.key is String && entry.value is String && (entry.value as String).isNotEmpty) {
        sources[entry.key as String] = entry.value as String;
      }
    }

    final clips = rawClips.map((value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Elemento del piano MagicIAedit non valido.');
      }
      final clip = MagicIAeditPlanClip.fromJson(value);
      if (!sources.containsKey(clip.assetId)) {
        throw FormatException('Media locale non trovato per ${clip.assetId}.');
      }
      return clip;
    }).toList(growable: false);

    final computedDuration = clips.fold<int>(
      0,
      (end, clip) => end > clip.startMs + clip.durationMs
          ? end
          : clip.startMs + clip.durationMs,
    );
    final rawDuration = result['durationMs'];
    final duration = rawDuration is int && rawDuration >= 0
        ? rawDuration
        : computedDuration;

    return MagicIAeditPlan._(
      title: _boundedString(result['title'], 'Montaggio MagicIAedit', 100),
      description: _boundedString(result['description'], '', 500),
      durationMs: duration,
      clips: List.unmodifiable(clips),
      sourcePaths: Map.unmodifiable(sources),
    );
  }

  /// Applies the reviewed proposal as the project's new visual montage while
  /// retaining audio and text tracks already present in the project.
  EditorProject applyTo(EditorProject project) {
    final videoClips = <EditorClip>[];
    final imageClips = <EditorClip>[];

    for (var index = 0; index < clips.length; index++) {
      final proposed = clips[index];
      final source = sourcePaths[proposed.assetId]!;
      final extension = source.toLowerCase().split('.').last;
      final MediaKind kind;
      if (_magicImageExtensions.contains(extension)) {
        kind = MediaKind.image;
      } else if (_magicVideoExtensions.contains(extension)) {
        kind = MediaKind.video;
      } else {
        throw FormatException('Formato non supportato nel piano: $extension');
      }
      final clip = EditorClip(
        id: 'magicia_${project.id}_$index',
        source: source,
        kind: kind,
        startMs: proposed.startMs,
        durationMs: proposed.durationMs,
        sourceStartMs: proposed.sourceStartMs,
        title: proposed.reason.isEmpty ? source.split(RegExp(r'[/\\\\]')).last : proposed.reason,
        transitionAfterMs: proposed.transitionAfterMs,
        transitionAfter: proposed.transitionAfter,
      );
      if (kind == MediaKind.video) {
        videoClips.add(clip);
      } else {
        imageClips.add(clip);
      }
    }

    final tracks = <EditorTrack>[
      if (videoClips.isNotEmpty)
        EditorTrack(
          id: 'magicia_${project.id}_video',
          name: 'MagicIAedit Video',
          kind: MediaKind.video,
          clips: List.unmodifiable(videoClips),
        ),
      if (imageClips.isNotEmpty)
        EditorTrack(
          id: 'magicia_${project.id}_images',
          name: 'MagicIAedit Foto',
          kind: MediaKind.image,
          clips: List.unmodifiable(imageClips),
        ),
      ...project.tracks.where(
        (track) => track.kind == MediaKind.audio || track.kind == MediaKind.text,
      ),
    ];
    return project.copyWith(
      name: title.trim().isEmpty ? project.name : title.trim(),
      tracks: List.unmodifiable(tracks),
    );
  }
}
