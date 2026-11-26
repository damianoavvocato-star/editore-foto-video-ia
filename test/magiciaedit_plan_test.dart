import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';
import 'package:editore_foto_video_ia/models/magiciaedit_plan.dart';

void main() {
  test('MagicIAedit plan applies source trims and preserves audio/text tracks', () {
    const project = EditorProject(
      id: 'project-1',
      name: 'Originale',
      tracks: [
        EditorTrack(
          id: 'old-video',
          name: 'Video originale',
          kind: MediaKind.video,
          clips: [
            EditorClip(
              id: 'old-clip',
              source: '/media/old.mp4',
              kind: MediaKind.video,
              startMs: 0,
              durationMs: 4000,
            ),
          ],
        ),
        EditorTrack(
          id: 'audio',
          name: 'Musica',
          kind: MediaKind.audio,
        ),
        EditorTrack(
          id: 'text',
          name: 'Titoli',
          kind: MediaKind.text,
        ),
      ],
    );

    final plan = MagicIAeditPlan.fromResult({
      'title': 'Il mio montaggio',
      'description': 'Una selezione automatica.',
      'durationMs': 6500,
      'sourcePaths': {
        'video-asset': '/media/scene.mp4',
        'image-asset': '/media/photo.jpg',
      },
      'clips': [
        {
          'assetId': 'video-asset',
          'sourceStartMs': 1250,
          'durationMs': 4000,
          'startMs': 0,
          'transitionAfterMs': 500,
          'transitionAfter': 'fade',
          'reason': 'Scena principale',
        },
        {
          'assetId': 'image-asset',
          'sourceStartMs': 0,
          'durationMs': 3000,
          'startMs': 3500,
          'transitionAfterMs': 0,
          'transitionAfter': 'fade',
          'reason': 'Foto finale',
        },
      ],
    });

    final applied = plan.applyTo(project);
    expect(applied.name, 'Il mio montaggio');
    expect(applied.tracks.map((track) => track.kind),
        [MediaKind.video, MediaKind.image, MediaKind.audio, MediaKind.text]);
    final video = applied.tracks.firstWhere((track) => track.kind == MediaKind.video);
    expect(video.clips.single.sourceStartMs, 1250);
    expect(video.clips.single.startMs, 0);
    expect(video.clips.single.transitionAfterMs, 500);
    expect(video.clips.single.source, '/media/scene.mp4');
    expect(applied.tracks.any((track) => track.id == 'old-video'), isFalse);
  });

  test('MagicIAedit rejects a plan that references an unknown local asset', () {
    expect(
      () => MagicIAeditPlan.fromResult({
        'sourcePaths': {'known': '/media/known.jpg'},
        'clips': [
          {
            'assetId': 'unknown',
            'sourceStartMs': 0,
            'durationMs': 3000,
            'startMs': 0,
            'transitionAfterMs': 0,
            'transitionAfter': 'fade',
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('MagicIAedit rejects invalid durations and unsupported transitions', () {
    expect(
      () => MagicIAeditPlan.fromResult({
        'sourcePaths': {'asset': '/media/clip.mp4'},
        'clips': [
          {
            'assetId': 'asset',
            'sourceStartMs': 0,
            'durationMs': 25000,
            'startMs': 0,
            'transitionAfterMs': 0,
            'transitionAfter': 'fade',
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MagicIAeditPlan.fromResult({
        'sourcePaths': {'asset': '/media/clip.mp4'},
        'clips': [
          {
            'assetId': 'asset',
            'sourceStartMs': 0,
            'durationMs': 3000,
            'startMs': 0,
            'transitionAfterMs': 0,
            'transitionAfter': 'random',
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('MagicIAedit rejects a plan without source mappings or too many clips', () {
    expect(
      () => MagicIAeditPlan.fromResult({'clips': []}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MagicIAeditPlan.fromResult({
        'sourcePaths': {'asset': '/media/clip.mp4'},
        'clips': List.generate(25, (index) => {
          'assetId': 'asset',
          'sourceStartMs': 0,
          'durationMs': 1000,
          'startMs': index * 1000,
          'transitionAfterMs': 0,
          'transitionAfter': 'fade',
        }),
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('MagicIAedit rejects unsupported source formats when applying a plan', () {
    final plan = MagicIAeditPlan.fromResult({
      'sourcePaths': {'asset': '/media/audio.mp3'},
      'clips': [
        {
          'assetId': 'asset',
          'sourceStartMs': 0,
          'durationMs': 3000,
          'startMs': 0,
          'transitionAfterMs': 0,
          'transitionAfter': 'fade',
        },
      ],
    });
    expect(
      () => plan.applyTo(const EditorProject(id: 'p', name: 'Project')),
      throwsA(isA<FormatException>()),
    );
  });
}
