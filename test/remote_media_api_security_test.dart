import 'package:flutter_test/flutter_test.dart';

import 'package:editore_foto_video_ia/services/remote_media_api.dart';

void main() {
  group('RemoteMediaApi transport security', () {
    test('rejects remote HTTP endpoints before any request is sent', () {
      expect(
        () => RemoteMediaApi(baseUri: Uri.parse('http://api.example.com')),
        throwsArgumentError,
      );
    });

    test('allows HTTPS endpoints for remote servers', () {
      final api = RemoteMediaApi(
        baseUri: Uri.parse('https://api.example.com'),
      );
      api.close();
    });

    test('allows loopback HTTP for local development', () {
      final api = RemoteMediaApi(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
      );
      api.close();
    });

    test('allows Android emulator host HTTP for local development', () {
      final api = RemoteMediaApi(
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );
      api.close();
    });

    test('rejects API base URLs containing paths or query parameters', () {
      expect(
        () => RemoteMediaApi(
          baseUri: Uri.parse('https://api.example.com/v1?tenant=demo'),
        ),
        throwsArgumentError,
      );
      expect(
        () => RemoteMediaApi(
          baseUri: Uri.parse('https://api.example.com/v1'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects URL-embedded credentials and fragments', () {
      expect(
        () => RemoteMediaApi(
          baseUri: Uri.parse('https://user:pass@api.example.com'),
        ),
        throwsArgumentError,
      );
      expect(
        () => RemoteMediaApi(
          baseUri: Uri.parse('https://api.example.com/#fragment'),
        ),
        throwsArgumentError,
      );
    });
  });
}
