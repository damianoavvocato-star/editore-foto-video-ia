import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/media/media_import_contract.dart';
import 'package:editore_foto_video_ia/media/import_to_timeline.dart';

void main() {
  test('creates sequential clips and advances insertion point', () {
    final result = createSequentialTimelineClips(
      insertionSeconds: 2,
      assets: const [
        ImportedMediaAsset(id: 'v1', path: '/a.mp4', kind: MediaKind.video, durationSeconds: 8),
        ImportedMediaAsset(id: 'i1', path: '/b.jpg', kind: MediaKind.image),
      ],
    );
    expect(result.clips, hasLength(2));
    expect(result.clips[0].timelineStartSeconds, 2);
    expect(result.clips[1].timelineStartSeconds, 10);
    expect(result.nextInsertionSeconds, 15);
  });

  test('rejects unknown media', () {
    expect(
      () => createSequentialTimelineClips(
        insertionSeconds: 0,
        assets: const [ImportedMediaAsset(id: 'x', path: '/x.bin', kind: MediaKind.unknown)],
      ),
      throwsArgumentError,
    );
  });
}

test('rejects duplicate asset IDs in one import batch', () {
  const asset = ImportedMediaAsset(
    id: 'same', path: '/same.mp4', kind: MediaKind.video, durationSeconds: 2,
  );
  expect(
    () => createSequentialTimelineClips(
      insertionSeconds: 0,
      assets: const [asset, asset],
    ),
    throwsArgumentError,
  );
});

test('rejects invalid size and MIME metadata before timeline insertion', () {
  const invalidSize = ImportedMediaAsset(
    id: 'bad-size', path: '/a.mp4', kind: MediaKind.video,
    durationSeconds: 2, fileSizeBytes: 0,
  );
  const invalidMime = ImportedMediaAsset(
    id: 'bad-mime', path: '/a.mp4', kind: MediaKind.video,
    durationSeconds: 2, mimeType: 'image/png',
  );
  for (final asset in [invalidSize, invalidMime]) {
    expect(
      () => createSequentialTimelineClips(insertionSeconds: 0, assets: [asset]),
      throwsArgumentError,
    );
  }
});
