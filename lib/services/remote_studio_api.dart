import '../models/studio_job.dart';
import 'account_api.dart';

class RemoteStudioApi {
  const RemoteStudioApi(this._accountApi);
  final RemoteAccountApi _accountApi;

  Future<Map<String, dynamic>> capabilities() =>
      _accountApi.request('GET', '/v1/studio/capabilities');

  Future<List<StudioJobDraft>> listDrafts({int limit = 50}) async {
    final response = await _accountApi.request('GET', '/v1/studio/jobs?limit=$limit');
    final values = response['jobs'];
    if (values is! List) throw const FormatException('Elenco progetti Studio non valido.');
    return values.whereType<Map>().map((value) =>
        StudioJobDraft.fromJson(Map<String, dynamic>.from(value))).toList(growable: false);
  }

  Future<StudioJobDraft> createDraft(StudioJobRequest request, {String? idempotencyKey}) async {
    request.validate();
    final headers = <String, String>{};
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      headers['Idempotency-Key'] = idempotencyKey;
    }
    final response = await _accountApi.request(
      'POST', '/v1/studio/jobs', body: request.toJson(), headers: headers,
    );
    return StudioJobDraft.fromJson(response);
  }

  Future<List<Map<String, dynamic>>> listQueue({int limit = 50}) async {
    final response = await _accountApi.request('GET', '/v1/studio/queue?limit=$limit');
    final values = response['jobs'];
    if (values is! List) throw const FormatException('Coda Studio non valida.');
    return values.whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
  }

  /// Explicitly queues a saved draft after user review. The server persists
  /// the request but does not start a paid provider generation.
  Future<Map<String, dynamic>> enqueueDraft(String jobId) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(jobId)) {
      throw ArgumentError.value(jobId, 'jobId', 'Identificativo bozza non valido.');
    }
    return _accountApi.request(
      'POST', '/v1/studio/jobs/${Uri.encodeComponent(jobId)}/enqueue',
    );
  }

  Future<void> deleteDraft(String jobId) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(jobId)) {
      throw ArgumentError.value(jobId, 'jobId', 'Identificativo bozza non valido.');
    }
    await _accountApi.request('DELETE', '/v1/studio/jobs/${Uri.encodeComponent(jobId)}');
  }

  void close() => _accountApi.close();
}
