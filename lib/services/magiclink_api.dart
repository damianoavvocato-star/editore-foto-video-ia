import 'account_api.dart';

class RemoteMagicLinkApi {
  const RemoteMagicLinkApi(this._accountApi);
  final RemoteAccountApi _accountApi;

  Future<Map<String, dynamic>> capabilities() =>
      _accountApi.request('GET', '/v1/magiclink/capabilities');

  Future<Map<String, dynamic>> analyze({
    required String url,
    String? instruction,
  }) {
    final normalized = url.trim();
    if (normalized.isEmpty || normalized.length > 2048) {
      throw ArgumentError.value(url, 'url', 'Inserisci un link valido (massimo 2048 caratteri).');
    }
    return _accountApi.request(
      'POST',
      '/v1/magiclink/analyze',
      body: {
        'url': normalized,
        if (instruction != null && instruction.trim().isNotEmpty)
          'instruction': instruction.trim(),
      },
    );
  }

  void close() => _accountApi.close();
}
