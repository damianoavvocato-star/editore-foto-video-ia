import 'media_import_contract.dart';

/// Timeline-neutral description of a clip created from an imported asset.
///
/// The host editor can map this DTO into its actual TimelineClip/EditorClip
/// model. Insertion time is supplied by the caller so timeline policy remains
/// in the application layer.
class ImportedTimelineClip {
  const ImportedTimelineClip({
    required this.assetId,
    required this.sourcePath,
    required this.kind,
    required this.timelineStartSeconds,
    required this.sourceInSeconds,
    required this.sourceOutSeconds,
    required this.speed,
  });

  final String assetId;
  final String sourcePath;
  final MediaKind kind;
  final double timelineStartSeconds;
  final double sourceInSeconds;
  final double sourceOutSeconds;
  final double speed;

  double get sourceDurationSeconds => sourceOutSeconds - sourceInSeconds;
  double get timelineDurationSeconds => sourceDurationSeconds / speed;
  double get timelineEndSeconds =>
      timelineStartSeconds + timelineDurationSeconds;
}

class TimelineInsertionResult {
  const TimelineInsertionResult({
    required this.clips,
    required this.nextInsertionSeconds,
  });

  final List<ImportedTimelineClip> clips;

  /// Suggested insertion point for a subsequent sequential import.
  final double nextInsertionSeconds;
}

/// Creates sequential, untrimmed clips from validated media.
///
/// Images are assigned a default display duration. This is a planning helper:
/// it does not mutate the app's editor state or write project files.
TimelineInsertionResult createSequentialTimelineClips({
  required Iterable<ImportedMediaAsset> assets,
  required double insertionSeconds,
  double imageDurationSeconds = 5,
}) {
  if (!insertionSeconds.isFinite || insertionSeconds < 0) {
    throw ArgumentError.value(insertionSeconds, 'insertionSeconds');
  }
  if (!imageDurationSeconds.isFinite || imageDurationSeconds <= 0) {
    throw ArgumentError.value(imageDurationSeconds, 'imageDurationSeconds');
  }

  var cursor = insertionSeconds;
  final clips = <ImportedTimelineClip>[];

  final seenIds = <String>{};
  for (final asset in assets) {
    final validationError = validateImportedMediaAsset(asset);
    if (validationError != null) {
      throw ArgumentError('Asset ${asset.id}: $validationError');
    }
    if (!seenIds.add(asset.id)) {
      throw ArgumentError('Duplicate imported asset ID: ${asset.id}');
    }

    final sourceDuration = switch (asset.kind) {
      MediaKind.video || MediaKind.audio =>
        asset.durationSeconds != null &&
                asset.durationSeconds!.isFinite &&
                asset.durationSeconds! > 0
            ? asset.durationSeconds!
            : throw ArgumentError('Asset ${asset.id} has invalid duration.'),
      MediaKind.image => imageDurationSeconds,
      MediaKind.unknown =>
        throw ArgumentError('Asset ${asset.id} has unknown media kind.'),
    };

    clips.add(ImportedTimelineClip(
      assetId: asset.id,
      sourcePath: asset.path,
      kind: asset.kind,
      timelineStartSeconds: cursor,
      sourceInSeconds: 0,
      sourceOutSeconds: sourceDuration,
      speed: 1,
    ));
    cursor += sourceDuration;
  }

  return TimelineInsertionResult(
    clips: List.unmodifiable(clips),
    nextInsertionSeconds: cursor,
  );
}
