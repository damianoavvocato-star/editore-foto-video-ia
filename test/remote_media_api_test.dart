import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/services/remote_media_api.dart';

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
