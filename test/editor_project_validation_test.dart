import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';

void main() {
  test('unknown clip media kind is rejected instead of becoming a video', () {
    expect(
      () => EditorClip.fromJson({
        'id': 'clip-1',
        'source': '/media/unknown.bin',
        'kind': 'document',
        'startMs': 0,
        'durationMs': 1000,
      }),
      throwsFormatException,
    );
  });

  test('unknown track media kind is rejected', () {
    expect(
      () => EditorTrack.fromJson({
        'id': 'track-1',
        'name': 'Unsupported',
        'kind': 'subtitle',
      }),
      throwsFormatException,
    );
  });

  test('known media kinds still round-trip', () {
    for (final kind in MediaKind.values) {
      final clip = EditorClip(
        id: 'clip-${kind.name}',
        source: '/media/${kind.name}',
        kind: kind,
        startMs: 0,
        durationMs: 1000,
      );
      expect(EditorClip.fromJson(clip.toJson()).kind, kind);
    }
  });

  test('future project schema versions are rejected explicitly', () {
    expect(
      () => EditorProject.fromJson({
        'schemaVersion': 2,
        'id': 'future',
        'name': 'Future project',
      }),
      throwsFormatException,
    );
  });

  test('legacy projects without schema version remain readable', () {
    final project = EditorProject.fromJson({
      'id': 'legacy',
      'name': 'Legacy project',
    });
    expect(project.id, 'legacy');
    expect(project.fps, 30);
  });

}
