import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/services/remote_media_api.dart';
import 'package:editore_foto_video_ia/services/ai_processing_service.dart';
import 'package:editore_foto_video_ia/models/editor_project.dart';
import 'package:editore_foto_video_ia/models/export_settings.dart';
import 'package:editore_foto_video_ia/services/export_coordinator.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('magic-media-test-');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('upload rejects empty files before opening a network request', () async {
    final file = File('${tempDirectory.path}/empty.mp4');
    await file.writeAsBytes([]);
    final api = RemoteMediaApi(baseUri: Uri.parse('https://media.example.test'));

    await expectLater(
      api.uploadFile(file.path),
      throwsArgumentError,
    );
    api.close();
  });

  test('upload rejects files above the backend 400 MB limit before network I/O', () async {
    final file = File('${tempDirectory.path}/too-large.mp4');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(RemoteMediaApi.maxUploadBytes + 1);
    await handle.close();
    final api = RemoteMediaApi(baseUri: Uri.parse('https://media.example.test'));

    await expectLater(
      api.uploadFile(file.path),
      throwsArgumentError,
    );
    api.close();
  });

  test('download rejects an oversized Content-Length without creating a file', () async {
    // HttpServer enforces Content-Length and will throw if the advertised body
    // is not sent. Use a raw socket to simulate a malicious/incorrect server.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final subscription = server.listen((socket) async {
      socket.add(utf8.encode(
        'HTTP/1.1 200 OK\\r\\n'
        'Content-Length: ${RemoteMediaApi.maxDownloadBytes + 1}\\r\\n'
        'Connection: close\\r\\n\\r\\n',
      ));
      await socket.flush();
      await socket.close();
    });
    final output = File('${tempDirectory.path}/oversized.bin');

    await expectLater(
      api.downloadFile('/oversized', output.path),
      throwsA(isA<FormatException>()),
    );
    expect(await output.exists(), isFalse);

    await subscription.cancel();
    await server.close();
    api.close();
  });

  test('failed download preserves an existing output and removes partial data', () async {
    // A raw socket is required to intentionally violate Content-Length;
    // HttpServer itself rejects and logs this malformed response.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final subscription = server.listen((socket) async {
      socket.add(utf8.encode(
        'HTTP/1.1 200 OK\\r\\n'
        'Content-Length: 10\\r\\n'
        'Connection: close\\r\\n\\r\\n'
      ));
      socket.add([1, 2, 3]);
      await socket.flush();
      await socket.close();
    });
    final output = File('${tempDirectory.path}/existing.bin');
    await output.writeAsBytes([9, 8, 7]);

    await expectLater(
      api.downloadFile('/truncated', output.path),
      throwsA(anything),
    );
    expect(await output.readAsBytes(), [9, 8, 7]);
    expect(await File('${output.path}.part').exists(), isFalse);

    await subscription.cancel();
    await server.close();
    api.close();
  });

  test('download URLs must stay on the API origin', () async {
    final api = RemoteMediaApi(baseUri: Uri.parse('https://media.example.test'));
    await expectLater(
      api.downloadFile(
        'https://attacker.example/steal',
        '${tempDirectory.path}/download.bin',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await File('${tempDirectory.path}/download.bin').exists(), isFalse);
    api.close();
  });

  test('API request paths cannot change the destination host', () async {
    final api = RemoteMediaApi(baseUri: Uri.parse('https://media.example.test'));
    await expectLater(
      api.request('GET', '//attacker.example/collect'),
      throwsA(isA<ArgumentError>()),
    );
    api.close();
  });

  test('API client rejects redirects instead of forwarding bearer credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      bearerToken: 'local-test-token',
    );
    server.listen((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer local-test-token',
      );
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'https://attacker.example/collect',
      );
      await request.response.close();
    });

    await expectLater(
      api.request('GET', '/redirect'),
      throwsA(isA<HttpException>()),
    );
    api.close();
    await server.close(force: true);
  });

  test('API errors do not expose raw server response bodies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final subscription = server.listen((request) async {
      await request.drain();
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('private server traceback and secrets');
      await request.response.close();
    });

    await expectLater(
      api.request('GET', '/failure'),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          isNot(contains('private server traceback')),
        ),
      ),
    );
    await subscription.cancel();
    api.close();
    await server.close(force: true);
  });

  test('API base URL rejects embedded credentials', () {
    expect(
      () => RemoteMediaApi(
        baseUri: Uri.parse('https://user:password@media.example.test'),
      ),
      throwsArgumentError,
    );
  });

  test('MagicIAedit maps uploaded asset IDs to local source paths', () async {
    final source = File('${tempDirectory.path}/scene.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final subscription = server.listen((request) async {
      await request.drain();
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/v1/assets':
          request.response.write(jsonEncode({'assetId': 'asset-1'}));
          break;
        case '/v1/ai/jobs':
          request.response.write(jsonEncode({'jobId': 'magic-job'}));
          break;
        case '/v1/jobs/magic-job':
          request.response.write(jsonEncode({
            'state': 'succeeded',
            'progress': 1,
            'result': {
              'title': 'Montaggio',
              'clips': [
                {
                  'assetId': 'asset-1',
                  'sourceStartMs': 0,
                  'durationMs': 1000,
                  'startMs': 0,
                  'transitionAfterMs': 0,
                  'transitionAfter': 'fade',
                },
              ],
            },
          }));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      api.close();
      await server.close(force: true);
    });

    final backend = RemoteAiBackend(api, pollInterval: Duration.zero);
    final request = AiTaskRequest(
      jobId: 'magic-job',
      task: AiTaskKind.magicIAedit,
      inputPath: source.path,
      inputPaths: [source.path],
    );
    final updates = await backend.run(request).toList();

    expect(updates.last.state, AiJobState.succeeded);
    expect(
      updates.last.result?['sourcePaths'],
      {'asset-1': source.path},
    );
  });

  test('remote AI cancellation during upload prevents job creation', () async {
    final source = File('${tempDirectory.path}/scene.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final uploadReceived = Completer<void>();
    final releaseUpload = Completer<void>();
    var aiJobCreated = false;
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final subscription = server.listen((request) async {
      await request.drain();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v1/assets') {
        uploadReceived.complete();
        await releaseUpload.future;
        request.response.write(jsonEncode({'assetId': 'asset-cancel'}));
      } else if (request.uri.path == '/v1/ai/jobs') {
        aiJobCreated = true;
        request.response.write(jsonEncode({'jobId': 'server-job'}));
      }
      await request.response.close();
    });
    addTearDown(() async {
      if (!releaseUpload.isCompleted) releaseUpload.complete();
      await subscription.cancel();
      api.close();
      await server.close(force: true);
    });

    final backend = RemoteAiBackend(api, pollInterval: Duration.zero);
    final states = <AiJobState>[];
    final done = Completer<void>();
    backend.run(AiTaskRequest(
      jobId: 'client-job',
      task: AiTaskKind.magicIAedit,
      inputPath: source.path,
      inputPaths: [source.path],
    )).listen(
      (progress) => states.add(progress.state),
      onError: done.completeError,
      onDone: done.complete,
    );

    await uploadReceived.future;
    await backend.cancel('client-job');
    releaseUpload.complete();
    await done.future;

    expect(states, [AiJobState.cancelled]);
    expect(aiJobCreated, isFalse);
  });

  test('remote AI cancellation targets the server-generated job ID', () async {
    final source = File('${tempDirectory.path}/scene.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final statusRequested = Completer<void>();
    final deletionReceived = Completer<String>();
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final subscription = server.listen((request) async {
      await request.drain();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v1/assets') {
        request.response.write(jsonEncode({'assetId': 'asset-remote'}));
      } else if (request.uri.path == '/v1/ai/jobs') {
        request.response.write(jsonEncode({'jobId': 'server-generated-job'}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/jobs/server-generated-job') {
        if (!statusRequested.isCompleted) statusRequested.complete();
        request.response.write(jsonEncode({
          'state': 'queued',
          'progress': 0,
          'message': 'In coda',
        }));
      } else if (request.method == 'DELETE') {
        deletionReceived.complete(request.uri.path);
        request.response.write(jsonEncode({'ok': true}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      api.close();
      await server.close(force: true);
    });

    final backend = RemoteAiBackend(api, pollInterval: const Duration(seconds: 1));
    final states = <AiJobState>[];
    final done = Completer<void>();
    backend.run(AiTaskRequest(
      jobId: 'client-side-job-id',
      task: AiTaskKind.magicIAedit,
      inputPath: source.path,
      inputPaths: [source.path],
    )).listen(
      (progress) => states.add(progress.state),
      onError: done.completeError,
      onDone: done.complete,
    );

    await statusRequested.future;
    await backend.cancel('client-side-job-id');
    expect(await deletionReceived.future, '/v1/jobs/server-generated-job');
    await done.future;
    expect(states, contains(AiJobState.cancelled));
  });

  test('remote render cancellation during upload prevents job creation', () async {
    final source = File('${tempDirectory.path}/render.mp4');
    await source.writeAsBytes([1, 2, 3, 4]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final uploadReceived = Completer<void>();
    final releaseUpload = Completer<void>();
    var renderJobCreated = false;
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final subscription = server.listen((request) async {
      await request.drain();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v1/assets') {
        uploadReceived.complete();
        await releaseUpload.future;
        request.response.write(jsonEncode({'assetId': 'render-asset'}));
      } else if (request.uri.path == '/v1/render/jobs') {
        renderJobCreated = true;
        request.response.write(jsonEncode({'jobId': 'render-server-job'}));
      }
      await request.response.close();
    });
    addTearDown(() async {
      if (!releaseUpload.isCompleted) releaseUpload.complete();
      await subscription.cancel();
      api.close();
      await server.close(force: true);
    });

    final backend = RemoteRenderBackend(api, pollInterval: Duration.zero);
    final request = ExportRequest(
      project: EditorProject(
        id: 'render-cancel',
        name: 'Render cancel',
        tracks: [
          EditorTrack(
            id: 'video-track',
            name: 'Video',
            kind: MediaKind.video,
            clips: [
              EditorClip(
                id: 'video-clip',
                source: source.path,
                kind: MediaKind.video,
                startMs: 0,
                durationMs: 1000,
              ),
            ],
          ),
        ],
      ),
      settings: const ExportSettings(),
      outputPath: '${tempDirectory.path}/output.mp4',
    );
    final phases = <ExportPhase>[];
    final done = Completer<void>();
    backend.render(request).listen(
      (progress) => phases.add(progress.phase),
      onError: done.completeError,
      onDone: done.complete,
    );

    await uploadReceived.future;
    await backend.cancel();
    releaseUpload.complete();
    await done.future;

    expect(phases, contains(ExportPhase.cancelled));
    expect(renderJobCreated, isFalse);
  });

  test('remote render uploads media, polls completion and downloads output', () async {
    final source = File('${tempDirectory.path}/render-source.mp4');
    await source.writeAsBytes([9, 8, 7, 6]);
    final output = '${tempDirectory.path}/rendered.mp4';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = RemoteMediaApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final subscription = server.listen((request) async {
      await request.drain();
      if (request.uri.path == '/v1/assets') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'assetId': 'render-source-asset'}));
      } else if (request.uri.path == '/v1/render/jobs') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'jobId': 'render-server-job'}));
      } else if (request.uri.path == '/v1/jobs/render-server-job') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'state': 'completed',
          'progress': 1,
          'downloadUrl': '/v1/outputs/render-server-job',
          'message': 'Rendering completato',
        }));
      } else if (request.uri.path == '/v1/outputs/render-server-job') {
        request.response.headers.contentType = ContentType.binary;
        request.response.add([1, 2, 3, 4, 5]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      api.close();
      await server.close(force: true);
    });

    final backend = RemoteRenderBackend(api, pollInterval: Duration.zero);
    final request = ExportRequest(
      project: EditorProject(
        id: 'render-success',
        name: 'Render success',
        tracks: [
          EditorTrack(
            id: 'video-track',
            name: 'Video',
            kind: MediaKind.video,
            clips: [
              EditorClip(
                id: 'video-clip',
                source: source.path,
                kind: MediaKind.video,
                startMs: 0,
                durationMs: 1000,
              ),
            ],
          ),
        ],
      ),
      settings: const ExportSettings(),
      outputPath: output,
    );

    final progress = await backend.render(request).toList();

    expect(progress.last.phase, ExportPhase.completed);
    expect(progress.last.outputPath, output);
    expect(await File(output).readAsBytes(), [1, 2, 3, 4, 5]);
  });

  test('remote render rejects URL sources the backend cannot resolve', () async {
    final api = RemoteMediaApi(baseUri: Uri.parse('https://example.invalid'));
    final backend = RemoteRenderBackend(api);
    final request = ExportRequest(
      project: const EditorProject(
        id: 'remote-source',
        name: 'Remote source',
        tracks: [
          EditorTrack(
            id: 'video-track',
            name: 'Video',
            kind: MediaKind.video,
            clips: [
              EditorClip(
                id: 'video-clip',
                source: 'https://cdn.example.test/video.mp4',
                kind: MediaKind.video,
                startMs: 0,
                durationMs: 1000,
              ),
            ],
          ),
        ],
      ),
      settings: const ExportSettings(),
      outputPath: '${tempDirectory.path}/output.mp4',
    );

    await expectLater(
      backend.render(request).toList(),
      throwsA(isA<ArgumentError>()),
    );
    api.close();
  });

  test('MagicIAedit rejects images above 20 MB before upload', () async {
    final image = File('${tempDirectory.path}/large.jpg');
    final imageHandle = await image.open(mode: FileMode.write);
    await imageHandle.truncate(20 * 1024 * 1024 + 1);
    await imageHandle.close();
    final api = RemoteMediaApi(baseUri: Uri.parse('https://example.invalid'));
    final backend = RemoteAiBackend(api);
    await expectLater(
      backend.validateMagicIAeditMediaPaths([image.path]),
      throwsA(isA<ArgumentError>()),
    );
    api.close();
  });

  test('MagicIAedit rejects selections above 400 MB before upload', () async {
    final paths = <String>[];
    for (var index = 0; index < 5; index++) {
      final file = File('${tempDirectory.path}/clip-$index.mp4');
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(90 * 1024 * 1024);
      await handle.close();
      paths.add(file.path);
    }
    final api = RemoteMediaApi(baseUri: Uri.parse('https://example.invalid'));
    final backend = RemoteAiBackend(api);
    await expectLater(
      backend.validateMagicIAeditMediaPaths(paths),
      throwsA(isA<ArgumentError>()),
    );
    api.close();
  });
}
