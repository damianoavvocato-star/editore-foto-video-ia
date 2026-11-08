import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';
import 'package:editore_foto_video_ia/models/export_settings.dart';
import 'package:editore_foto_video_ia/services/export_coordinator.dart';

void main() {
  const emptyProject = EditorProject(id: 'empty', name: 'Empty');

  test('export request rejects empty timeline', () {
    const request = ExportRequest(
      project: emptyProject,
      settings: ExportSettings(),
      outputPath: '/tmp/output.mp4',
    );
    expect(request.validate, throwsA(isA<StateError>()));
  });

  test('export request rejects negative clip start and invalid speed', () {
    const project = EditorProject(
      id: 'invalid',
      name: 'Invalid',
      tracks: [
        EditorTrack(
          id: 'v',
          name: 'Video',
          kind: MediaKind.video,
          clips: [
            EditorClip(
              id: 'c',
              source: '/tmp/clip.mp4',
              kind: MediaKind.video,
              startMs: -1,
              durationMs: 1000,
              speed: 1,
            ),
          ],
        ),
      ],
    );
    const request = ExportRequest(
      project: project,
      settings: ExportSettings(),
      outputPath: '/tmp/output.mp4',
    );
    expect(request.validate, throwsA(isA<StateError>()));
  });

  test('export request rejects bitrate outside supported range', () {
    const project = EditorProject(
      id: 'p',
      name: 'P',
      tracks: [
        EditorTrack(
          id: 'v',
          name: 'Video',
          kind: MediaKind.video,
          clips: [
            EditorClip(
              id: 'c',
              source: '/tmp/clip.mp4',
              kind: MediaKind.video,
              startMs: 0,
              durationMs: 1000,
            ),
          ],
        ),
      ],
    );
    const request = ExportRequest(
      project: project,
      settings: ExportSettings(bitrateMbps: 101),
      outputPath: '/tmp/output.mp4',
    );
    expect(request.validate, throwsRangeError);
  });

  test('export request requires output path', () {
    const project = EditorProject(
      id: 'p',
      name: 'P',
      tracks: [
        EditorTrack(
          id: 'v',
          name: 'Video',
          kind: MediaKind.video,
          clips: [
            EditorClip(
              id: 'c',
              source: '/tmp/clip.mp4',
              kind: MediaKind.video,
              startMs: 0,
              durationMs: 1000,
            ),
          ],
        ),
      ],
    );
    const request = ExportRequest(
      project: project,
      settings: ExportSettings(),
      outputPath: ' ',
    );
    expect(request.validate, throwsA(isA<ArgumentError>()));
  });

  test('export request rejects empty source paths', () {
    const project = EditorProject(
      id: 'p', name: 'P',
      tracks: [EditorTrack(id: 'v', name: 'Video', kind: MediaKind.video,
        clips: [EditorClip(id: 'c', source: ' ', kind: MediaKind.video,
          startMs: 0, durationMs: 1000)])],
    );
    const request = ExportRequest(project: project, settings: ExportSettings(), outputPath: '/tmp/out.mp4');
    expect(request.validate, throwsA(isA<StateError>()));
  });

  test('export request rejects duplicate clip IDs across tracks', () {
    const clip = EditorClip(id: 'same', source: '/tmp/a.mp4', kind: MediaKind.video,
      startMs: 0, durationMs: 1000);
    const project = EditorProject(id: 'p', name: 'P', tracks: [
      EditorTrack(id: 'v1', name: 'Video 1', kind: MediaKind.video, clips: [clip]),
      EditorTrack(id: 'v2', name: 'Video 2', kind: MediaKind.video, clips: [clip]),
    ]);
    const request = ExportRequest(project: project, settings: ExportSettings(), outputPath: '/tmp/out.mp4');
    expect(request.validate, throwsA(isA<StateError>()));
  });

  test('export request rejects transition longer than its clip', () {
    const project = EditorProject(id: 'p', name: 'P', tracks: [
      EditorTrack(id: 'v', name: 'Video', kind: MediaKind.video, clips: [
        EditorClip(id: 'c', source: '/tmp/a.mp4', kind: MediaKind.video,
          startMs: 0, durationMs: 1000, transitionAfterMs: 1001),
      ]),
    ]);
    const request = ExportRequest(project: project, settings: ExportSettings(), outputPath: '/tmp/out.mp4');
    expect(request.validate, throwsA(isA<StateError>()));
  });


  test('export request rejects invalid project frame rate', () {
    const project = EditorProject(id: 'p', name: 'P', fps: 0, tracks: [
      EditorTrack(id: 'v', name: 'Video', kind: MediaKind.video, clips: [
        EditorClip(id: 'c', source: '/tmp/a.mp4', kind: MediaKind.video,
          startMs: 0, durationMs: 1000),
      ]),
    ]);
    const request = ExportRequest(project: project, settings: ExportSettings(),
      outputPath: '/tmp/out.mp4');
    expect(request.validate, throwsRangeError);
  });

  test('export request rejects duplicate track IDs', () {
    const clip1 = EditorClip(id: 'c1', source: '/tmp/a.mp4', kind: MediaKind.video,
      startMs: 0, durationMs: 1000);
    const clip2 = EditorClip(id: 'c2', source: '/tmp/b.mp4', kind: MediaKind.video,
      startMs: 0, durationMs: 1000);
    const project = EditorProject(id: 'p', name: 'P', tracks: [
      EditorTrack(id: 'same', name: 'Video 1', kind: MediaKind.video, clips: [clip1]),
      EditorTrack(id: 'same', name: 'Video 2', kind: MediaKind.video, clips: [clip2]),
    ]);
    const request = ExportRequest(project: project, settings: ExportSettings(),
      outputPath: '/tmp/out.mp4');
    expect(request.validate, throwsA(isA<StateError>()));
  });

  test('export request rejects projects above track limit', () {
    final tracks = List.generate(65, (i) => EditorTrack(
      id: 'track-$i', name: 'Track $i', kind: MediaKind.video,
      clips: [EditorClip(id: 'clip-$i', source: '/tmp/a.mp4',
        kind: MediaKind.video, startMs: 0, durationMs: 1000)],
    ));
    final request = ExportRequest(
      project: EditorProject(id: 'p', name: 'P', tracks: tracks),
      settings: const ExportSettings(), outputPath: '/tmp/out.mp4');
    expect(request.validate, throwsA(isA<StateError>()));
  });


  test('export request rejects resolutions above the supported 8K bound', () {
    const project = EditorProject(id: 'p', name: 'P', width: 10000, height: 6000, tracks: [
      EditorTrack(id: 'v', name: 'Video', kind: MediaKind.video, clips: [
        EditorClip(id: 'c', source: '/tmp/a.mp4', kind: MediaKind.video,
          startMs: 0, durationMs: 1000),
      ]),
    ]);
    const request = ExportRequest(project: project, settings: ExportSettings(),
      outputPath: '/tmp/out.mp4');
    expect(request.validate, throwsA(isA<StateError>()));
  });

  test('export request rejects track IDs with surrounding whitespace', () {
    const project = EditorProject(id: 'p', name: 'P', tracks: [
      EditorTrack(id: ' video ', name: 'Video', kind: MediaKind.video, clips: [
        EditorClip(id: 'c', source: '/tmp/a.mp4', kind: MediaKind.video,
          startMs: 0, durationMs: 1000),
      ]),
    ]);
    const request = ExportRequest(project: project, settings: ExportSettings(),
      outputPath: '/tmp/out.mp4');
    expect(request.validate, throwsA(isA<StateError>()));
  });

  test('coordinator reports synchronous backend startup errors and unlocks', () async {
    final backend = _ThrowingStartupBackend();
    final coordinator = ExportCoordinator(backend);
    const project = EditorProject(id: 'p', name: 'P', tracks: [
      EditorTrack(id: 'v', name: 'Video', kind: MediaKind.video, clips: [
        EditorClip(id: 'c', source: '/tmp/a.mp4', kind: MediaKind.video,
          startMs: 0, durationMs: 1000),
      ]),
    ]);
    const request = ExportRequest(project: project, settings: ExportSettings(),
      outputPath: '/tmp/out.mp4');

    final events = await coordinator.start(request).toList();
    expect(events.last.phase, ExportPhase.failed);
    expect(events.last.error, isA<StateError>());
    // A failed startup must release the active slot for a later attempt.
    final secondEvents = await coordinator.start(request).toList();
    expect(secondEvents.last.phase, ExportPhase.failed);
    expect(backend.calls, 2);
  });

  test('coordinator cancels renderer subscription and emits cancelled state', () async {
    final backend = _CancellableBackend();
    final coordinator = ExportCoordinator(backend);
    const project = EditorProject(id: 'p', name: 'P', tracks: [
      EditorTrack(id: 'v', name: 'Video', kind: MediaKind.video, clips: [
        EditorClip(id: 'c', source: '/tmp/a.mp4', kind: MediaKind.video,
          startMs: 0, durationMs: 1000),
      ]),
    ]);
    const request = ExportRequest(
      project: project,
      settings: ExportSettings(),
      outputPath: '/tmp/out.mp4',
    );

    final events = <ExportProgress>[];
    final cancelled = Completer<ExportProgress>();

    final subscription = coordinator.start(request).listen((event) {
      events.add(event);
      if (event.phase == ExportPhase.cancelled && !cancelled.isCompleted) {
        cancelled.complete(event);
      }
    });

    await Future<void>.delayed(Duration.zero);
    await coordinator.cancel();

    final terminalEvent = await cancelled.future.timeout(
      const Duration(seconds: 2),
    );
    await subscription.cancel();

    expect(backend.cancelCalls, 1);
    expect(terminalEvent.phase, ExportPhase.cancelled);
    expect(terminalEvent.isTerminal, isTrue);
    expect(events.last.phase, ExportPhase.cancelled);
  });

  test('coordinator reports failure when backend closes without terminal result', () async {
    final coordinator = ExportCoordinator(_SilentCompletionBackend());
    const project = EditorProject(id: 'p', name: 'P', tracks: [
      EditorTrack(id: 'v', name: 'Video', kind: MediaKind.video, clips: [
        EditorClip(id: 'c', source: '/tmp/a.mp4', kind: MediaKind.video,
          startMs: 0, durationMs: 1000),
      ]),
    ]);
    const request = ExportRequest(project: project, settings: ExportSettings(),
      outputPath: '/tmp/out.mp4');

    final events = await coordinator.start(request).toList();
    expect(events.last.phase, ExportPhase.failed);
    expect(events.last.message, contains('senza comunicare un esito'));
  });

}

class _SilentCompletionBackend implements MediaRenderBackend {
  @override
  Stream<ExportProgress> render(ExportRequest request) => const Stream.empty();
  @override
  Future<void> cancel() async {}
}

class _ThrowingStartupBackend implements MediaRenderBackend {
  int calls = 0;

  @override
  Stream<ExportProgress> render(ExportRequest request) {
    calls++;
    throw StateError('Native renderer unavailable');
  }

  @override
  Future<void> cancel() async {}
}


class _CancellableBackend implements MediaRenderBackend {
  final StreamController<ExportProgress> controller = StreamController<ExportProgress>();
  int cancelCalls = 0;

  @override
  Stream<ExportProgress> render(ExportRequest request) => controller.stream;

  @override
  Future<void> cancel() async { cancelCalls++; }
}
