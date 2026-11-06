import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/services/remote_media_api.dart';
import 'package:editore_foto_video_ia/services/ai_processing_service.dart';

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
        case '/v1/ai/jobs':
          request.response.write(jsonEncode({'jobId': 'magic-job'}));
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
    const request = AiTaskRequest(
      jobId: 'magic-job',
      task: AiTaskKind.magicIAedit,
      inputPath: '',
      inputPaths: [],
    );
    final actualRequest = AiTaskRequest(
      jobId: request.jobId,
      task: request.task,
      inputPath: source.path,
      inputPaths: [source.path],
    );
    final updates = await backend.run(actualRequest).toList();

    expect(updates.last.state, AiJobState.succeeded);
    expect(
      updates.last.result?['sourcePaths'],
      {'asset-1': source.path},
    );
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
