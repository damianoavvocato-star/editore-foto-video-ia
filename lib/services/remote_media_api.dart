import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_processing_service.dart';
import 'export_coordinator.dart';

/// HTTP adapter for a separately deployed AI/render service.
/// API contract: POST /v1/ai/jobs, GET /v1/jobs/{id}, DELETE /v1/jobs/{id};
/// POST /v1/render/jobs, GET /v1/jobs/{id}, DELETE /v1/jobs/{id}.
/// The server is responsible for actual ML inference and media encoding.
class RemoteMediaApi {
  RemoteMediaApi({required Uri baseUri, HttpClient? client, this.bearerToken})
      : baseUri = baseUri,
        _client = client ?? HttpClient() {
    if (!baseUri.hasScheme || !{'http', 'https'}.contains(baseUri.scheme)) {
      throw ArgumentError.value(baseUri, 'baseUri', 'È richiesto un URL HTTP(S).');
    }
    if (baseUri.userInfo.isNotEmpty || baseUri.fragment.isNotEmpty) {
      throw ArgumentError.value(
        baseUri,
        'baseUri',
        'L’indirizzo API non può contenere credenziali o frammenti.',
      );
    }
  }

  final Uri baseUri;
  final HttpClient _client;
  final String? bearerToken;
  static const Duration requestTimeout = Duration(minutes: 3);

  bool _hasSameOrigin(Uri uri) =>
      uri.scheme.toLowerCase() == baseUri.scheme.toLowerCase() &&
      uri.host.toLowerCase() == baseUri.host.toLowerCase() &&
      uri.port == baseUri.port;

  Uri _resolveApiUri(String path) {
    final uri = baseUri.resolve(path);
    if (!_hasSameOrigin(uri) || uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
      throw ArgumentError.value(path, 'path', 'L’API deve restare sullo stesso host.');
    }
    return uri;
  }

  Uri _resolveDownloadUri(String downloadUrl) {
    final parsed = Uri.parse(downloadUrl);
    final uri = parsed.hasScheme ? parsed : baseUri.resolveUri(parsed);
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !_hasSameOrigin(uri) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError.value(
        downloadUrl,
        'downloadUrl',
        'Il download deve provenire dallo stesso host dell’API.',
      );
    }
    return uri;
  }

  void _authorize(HttpClientRequest req) {
    if (bearerToken != null && bearerToken!.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    }
  }

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, Object?>? body}) async {
    final uri = _resolveApiUri(path);
    final req = await _client.openUrl(method, uri).timeout(requestTimeout);
    req.followRedirects = false;
    req.headers.contentType = ContentType.json;
    _authorize(req);
    if (body != null) req.write(jsonEncode(body));
    final response = await req.close().timeout(requestTimeout);
    final text = await response.transform(utf8.decoder).join().timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Media API HTTP ${response.statusCode}: $text', uri: uri);
    }
    if (text.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Risposta API non valida: atteso un oggetto JSON.');
    }
    return decoded;
  }

  /// Uploads a local media file. The API must return {"assetId": "..."}.
  Future<String> uploadFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw FileSystemException('Media sorgente non trovato', filePath);
    final boundary = '----EditoreMedia${DateTime.now().microsecondsSinceEpoch}';
    final uri = _resolveApiUri('/v1/assets');
    final req = await _client.postUrl(uri).timeout(requestTimeout);
    req.followRedirects = false;
    _authorize(req);
    req.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
    final filename = Uri.encodeComponent(file.uri.pathSegments.last);
    Stream<List<int>> multipartBody() async* {
      yield utf8.encode('--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$filename"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n');
      yield* file.openRead();
      yield utf8.encode('\r\n--$boundary--\r\n');
    }
    await req.addStream(multipartBody());
    final response = await req.close().timeout(requestTimeout);
    final body = await response.transform(utf8.decoder).join().timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Upload fallito HTTP ${response.statusCode}: $body', uri: uri);
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['assetId'] == null || decoded['assetId'].toString().isEmpty) {
      throw const FormatException('Upload: risposta senza assetId.');
    }
    return decoded['assetId'].toString();
  }

  /// Downloads a completed asset to the requested local destination.
  Future<void> downloadFile(String downloadUrl, String outputPath) async {
    final uri = _resolveDownloadUri(downloadUrl);
    final req = await _client.getUrl(uri).timeout(requestTimeout);
    req.followRedirects = false;
    _authorize(req);
    final response = await req.close().timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = await response.transform(utf8.decoder).join();
      throw HttpException('Download fallito HTTP ${response.statusCode}: $detail', uri: uri);
    }
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    final sink = output.openWrite();
    try {
      await response.pipe(sink).timeout(const Duration(minutes: 30));
    } catch (_) {
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  void close() => _client.close(force: true);
}

class RemoteAiBackend implements AiProcessingBackend {
  RemoteAiBackend(this.api, {this.pollInterval = const Duration(seconds: 2)});
  final RemoteMediaApi api;
  final Duration pollInterval;
  final Set<String> _cancelled = {};
  final Map<String, String> _remoteJobs = {};

  @override
  Future<void> cancel(String jobId) async {
    _cancelled.add(jobId);
    final remoteId = _remoteJobs[jobId];
    // The upload/create phase may not have produced a server job yet.
    // run() observes the cancellation flag before creating one.
    if (remoteId != null) {
      await api.request('DELETE', '/v1/jobs/${Uri.encodeComponent(remoteId)}');
    }
  }

  static const int maxImageBytes = 20 * 1024 * 1024;
  static const int maxVideoBytes = 100 * 1024 * 1024;
  static const int maxSelectionBytes = 400 * 1024 * 1024;

  /// Check local file sizes before uploading anything, so an unsupported
  /// selection fails early and does not waste mobile data or server storage.
  Future<void> validateMagicIAeditMediaPaths(List<String> paths) async {
    if (paths.isEmpty || paths.length > 20) {
      throw ArgumentError('MagicIAedit accetta da 1 a 20 media.');
    }
    var totalBytes = 0;
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('Media sorgente non trovato', path);
      }
      final size = await file.length();
      final extension = path.toLowerCase().split('.').last;
      final isImage = {'jpg', 'jpeg', 'png', 'webp'}.contains(extension);
      final isVideo = {'mp4', 'mov', 'avi', 'webm', 'm4v'}.contains(extension);
      if (isImage && (size == 0 || size > maxImageBytes)) {
        throw ArgumentError('Ogni immagine per MagicIAedit deve essere inferiore a 20 MB.');
      }
      if (isVideo && (size == 0 || size > maxVideoBytes)) {
        throw ArgumentError('Ogni video per MagicIAedit deve essere inferiore a 100 MB.');
      }
      if (!isImage && !isVideo) {
        throw ArgumentError('Formato media non supportato da MagicIAedit.');
      }
      totalBytes += size;
      if (totalBytes > maxSelectionBytes) {
        throw ArgumentError('La selezione MagicIAedit supera 400 MB complessivi.');
      }
    }
  }

  @override
  Stream<AiJobProgress> run(AiTaskRequest request) async* {
    String? remoteId;
    try {
      if (request.task == AiTaskKind.magicIAedit) {
        await validateMagicIAeditMediaPaths(request.mediaPaths);
      }
      final assetIds = <String>[];
      for (final path in request.mediaPaths) {
        if (_cancelled.contains(request.jobId)) {
          yield AiJobProgress(
            jobId: request.jobId,
            task: request.task,
            state: AiJobState.cancelled,
            message: 'Caricamento annullato.',
          );
          return;
        }
        assetIds.add(await api.uploadFile(path));
      }
      if (_cancelled.contains(request.jobId)) {
        yield AiJobProgress(
          jobId: request.jobId,
          task: request.task,
          state: AiJobState.cancelled,
          message: 'Caricamento annullato.',
        );
        return;
      }

      final created = await api.request('POST', '/v1/ai/jobs', body: {
        'jobId': request.jobId,
        'task': request.task.name,
        'assetIds': assetIds,
        'options': request.options,
      });
      remoteId = (created['jobId'] ?? request.jobId).toString();
      if (remoteId!.isEmpty) {
        throw const FormatException('Il server non ha restituito jobId.');
      }
      _remoteJobs[request.jobId] = remoteId!;

      if (_cancelled.contains(request.jobId)) {
        await api.request('DELETE', '/v1/jobs/${Uri.encodeComponent(remoteId!)}');
        yield AiJobProgress(
          jobId: request.jobId,
          task: request.task,
          state: AiJobState.cancelled,
          message: 'Elaborazione annullata.',
        );
        return;
      }

      while (!_cancelled.contains(request.jobId)) {
        final status = await api.request(
          'GET',
          '/v1/jobs/${Uri.encodeComponent(remoteId!)}',
        );
        final state = (status['state'] ?? 'running').toString();
        final progress = ((status['progress'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0);
        final mapped = switch (state) {
          'queued' => AiJobState.queued,
          'succeeded' || 'completed' => AiJobState.succeeded,
          'failed' => AiJobState.failed,
          'cancelled' => AiJobState.cancelled,
          _ => AiJobState.running,
        };
        String? resultPath;
        if (mapped == AiJobState.succeeded) {
          final downloadUrl = status['downloadUrl']?.toString();
          if (downloadUrl != null && downloadUrl.isNotEmpty) {
            resultPath = '${request.inputPath}.ai-result';
            await api.downloadFile(downloadUrl, resultPath);
          } else {
            resultPath = status['resultPath']?.toString();
          }
        }
        final rawResult = status['result'];
        Map<String, dynamic>? result;
        if (rawResult is Map) {
          result = Map<String, dynamic>.from(rawResult);
          if (request.task == AiTaskKind.magicIAedit) {
            // Keep local file paths on-device so a reviewed plan can be applied
            // to the timeline without exposing those paths to the cloud service.
            result['sourcePaths'] = Map<String, String>.fromIterables(
              assetIds,
              request.mediaPaths,
            );
          }
        }
        yield AiJobProgress(
          jobId: request.jobId,
          task: request.task,
          state: mapped,
          fraction: progress,
          message: status['message']?.toString() ?? '',
          resultPath: resultPath,
          error: status['error'],
          result: result,
        );
        if (mapped == AiJobState.succeeded ||
            mapped == AiJobState.failed ||
            mapped == AiJobState.cancelled) {
          return;
        }
        await Future<void>.delayed(pollInterval);
      }
      yield AiJobProgress(
        jobId: request.jobId,
        task: request.task,
        state: AiJobState.cancelled,
        message: 'Elaborazione annullata.',
      );
    } finally {
      _remoteJobs.remove(request.jobId);
      _cancelled.remove(request.jobId);
    }
  }
}

class RemoteRenderBackend implements MediaRenderBackend {
  RemoteRenderBackend(this.api, {this.pollInterval = const Duration(seconds: 2)});
  final RemoteMediaApi api;
  final Duration pollInterval;
  String? _activeJobId;

  @override
  Future<void> cancel() async {
    final id = _activeJobId;
    if (id != null) await api.request('DELETE', '/v1/jobs/${Uri.encodeComponent(id)}');
    _activeJobId = null;
  }

  @override
  Stream<ExportProgress> render(ExportRequest request) async* {
    final projectJson = request.project.toJson();
    final tracks = projectJson['tracks'] as List<dynamic>;
    for (final trackValue in tracks) {
      final track = trackValue as Map<String, dynamic>;
      final clips = track['clips'] as List<dynamic>;
      for (final clipValue in clips) {
        final clip = clipValue as Map<String, dynamic>;
        final source = clip['source']?.toString() ?? '';
        if (source.startsWith('http://') || source.startsWith('https://')) continue;
        clip['assetId'] = await api.uploadFile(source);
        clip.remove('source');
      }
    }
    final created = await api.request('POST', '/v1/render/jobs', body: {
      'project': projectJson,
      'settings': {
        'container': request.settings.container.name,
        'resolution': request.settings.resolution.name,
        'codec': request.settings.codec.name,
        'fps': request.settings.framesPerSecond,
        'includeAudio': request.settings.includeAudio,
        'bitrateMbps': request.settings.bitrateMbps,
      },
    });
    final id = (created['jobId'] ?? '').toString();
    if (id.isEmpty) throw const FormatException('Il server non ha restituito jobId.');
    _activeJobId = id;
    while (_activeJobId == id) {
      final status = await api.request('GET', '/v1/jobs/${Uri.encodeComponent(id)}');
      final state = (status['state'] ?? 'rendering').toString();
      final fraction = ((status['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
      final phase = switch (state) {
        'queued' => ExportPhase.queued,
        'preparing' => ExportPhase.preparing,
        'finalizing' => ExportPhase.finalizing,
        'completed' || 'succeeded' => ExportPhase.completed,
        'failed' => ExportPhase.failed,
        'cancelled' => ExportPhase.cancelled,
        _ => ExportPhase.rendering,
      };
      if (phase == ExportPhase.completed) {
        final downloadUrl = status['downloadUrl']?.toString();
        if (downloadUrl == null || downloadUrl.isEmpty) {
          _activeJobId = null;
          throw const FormatException('Render completato ma il server non ha restituito downloadUrl.');
        }
        await api.downloadFile(downloadUrl, request.outputPath);
      }
      yield ExportProgress(phase: phase, fraction: fraction,
        message: status['message']?.toString() ?? '',
        outputPath: request.outputPath,
        error: status['error']);
      if (phase == ExportPhase.completed || phase == ExportPhase.failed || phase == ExportPhase.cancelled) {
        _activeJobId = null;
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
    yield const ExportProgress(phase: ExportPhase.cancelled, message: 'Esportazione annullata.');
  }
}
