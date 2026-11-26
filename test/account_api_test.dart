import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/services/account_api.dart';

void main() {
  group('RemoteAccountApi endpoint validation', () {
    test('requires HTTPS for non-local endpoints', () {
      expect(
        () => RemoteAccountApi(baseUri: Uri.parse('http://api.example.test')),
        throwsArgumentError,
      );
    });

    test('allows HTTPS and explicit local development HTTP endpoints', () {
      final secure = RemoteAccountApi(
        baseUri: Uri.parse('https://api.example.test'),
      );
      final local = RemoteAccountApi(
        baseUri: Uri.parse('http://10.0.2.2:8000'),
      );
      secure.close();
      local.close();
    });

    test('rejects endpoint user info, query and path components', () {
      for (final value in [
        'https://user:pass@api.example.test',
        'https://api.example.test?token=secret',
        'https://api.example.test/v1',
      ]) {
        expect(
          () => RemoteAccountApi(baseUri: Uri.parse(value)),
          throwsArgumentError,
        );
      }
    });
  });
}
