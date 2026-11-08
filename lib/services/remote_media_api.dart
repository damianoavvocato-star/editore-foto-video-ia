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
      : baseUri = _validateBaseUri(baseUri),
        _client = client ?? HttpClient();

  /// Reject clear-text remote endpoints at the transport boundary, not only
  /// in the UI. Bearer credentials and uploaded media must use HTTPS.
  /// Plain HTTP remains available for local development and Android emulator
  /// host access.
  static Uri _validateBaseUri(Uri uri) {
    if (!uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'baseUri', 'È richiesto un URL HTTP(S) con host valido.');
    }
    if (uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.query.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'L’indirizzo API deve essere un’origine senza credenziali, percorso, query o frammenti.',
      );
    }
    final localHttp = uri.scheme == 'http' &&
        {'localhost', '127.0.0.1', '10.0.2.2', '::1'}.contains(uri.host);
    if (uri.scheme == 'http' && !localHttp) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'HTTP non cifrato è consentito solo per endpoint locali; usa HTTPS per server remoti.',
      );
    }
    return uri;
  }

  final Uri baseUri;
  final HttpClient _client;
  final String? bearerToken;
  static const Duration requestTimeout = Duration(minutes: 3);
  static const int maxJsonResponseBytes = 8 * 1024 * 1024;
  // Keep client uploads aligned with the backend's per-file limit.
  static const int maxUploadBytes = 400 * 1024 * 1024;
  // Avoid unbounded disk consumption from a faulty or compromised media server.
  static const int maxDownloadBytes = 2 * 1024 * 1024 * 1024;

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

  Future<String> _readResponseText(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(requestTimeout)) {
      if (bytes.length + chunk.length > maxJsonResponseBytes) {
        throw const FormatException('Risposta del server troppo grande.');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
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
    final text = await _readResponseText(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Media API HTTP ${response.statusCode}', uri: uri);
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
    final fileSize = await file.length();
    if (fileSize == 0) throw ArgumentError('Il file multimediale è vuoto.');
    if (fileSize > maxUploadBytes) {
      throw ArgumentError('Il file supera il limite di upload di 400 MB.');
    }
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
    final body = await _readResponseText(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Upload fallito HTTP ${response.statusCode}', uri: uri);
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
      await response.drain<void>();
      throw HttpException('Download fallito HTTP ${response.statusCode}', uri: uri);
    }
    if (response.contentLength > maxDownloadBytes) {
      await response.drain<void>();
      throw const FormatException('Il file scaricato supera il limite di 2 GB.');
    }
    final output = File(outputPath);
    final temporary = File('${output.path}.part');
    await output.parent.create(recursive: true);
    IOSink? sink;
    try {
      sink = temporary.openWrite();
      var receivedBytes = 0;
      await for (final chunk in response.timeout(const Duration(minutes: 30))) {
        receivedBytes += chunk.length;
        if (receivedBytes > maxDownloadBytes) {
          throw const FormatException('Il file scaricato supera il limite di 2 GB.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // Replace an existing output only after the new download is complete.
      if (await output.exists()) await output.delete();
      await temporary.rename(output.path);
    } catch (_) {
      if (sink != null) await sink.close();
      if (await temporary.exists()) await temporary.delete();
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
      final remoteJobId = (created['jobId'] ?? request.jobId).toString();
      if (remoteJobId.isEmpty) {
        throw const FormatException('Il server non ha restituito jobId.');
      }
      _remoteJobs[request.jobId] = remoteJobId;

      if (_cancelled.contains(request.jobId)) {
        await api.request('DELETE', '/v1/jobs/${Uri.encodeComponent(remoteJobId)}');
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
          '/v1/jobs/${Uri.encodeComponent(remoteJobId)}',
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
  bool _rendering = false;
  bool _cancelRequested = false;

  @override
  Future<void> cancel() async {
    if (!_rendering) return;
    _cancelRequested = true;
    final id = _activeJobId;
    if (id != null) {
      await api.request('DELETE', '/v1/jobs/${Uri.encodeComponent(id)}');
      _activeJobId = null;
    }
  }

  @override
  Stream<ExportProgress> render(ExportRequest request) async* {
    _rendering = true;
    _cancelRequested = false;
    try {
      yield const ExportProgress(
        phase: ExportPhase.preparing,
        fraction: 0,
        message: 'Preparazione e caricamento dei media.',
      );
      final projectJson = request.project.toJson();
      final tracks = projectJson['tracks'] as List<dynamic>;
      for (final trackValue in tracks) {
        final track = trackValue as Map<String, dynamic>;
        final clips = track['clips'] as List<dynamic>;
        for (final clipValue in clips) {
          if (_cancelRequested) {
            yield const ExportProgress(
              phase: ExportPhase.cancelled,
              message: 'Esportazione annullata durante il caricamento.',
            );
            return;
          }
          final clip = clipValue as Map<String, dynamic>;
          final source = clip['source']?.toString().trim() ?? '';
          if (source.isEmpty) {
            throw const FormatException('Una clip non contiene un file sorgente.');
          }
          if (source.toLowerCase().startsWith('http://') ||
              source.toLowerCase().startsWith('https://')) {
            throw ArgumentError(
              'Il rendering remoto richiede file locali; importa prima il media nel progetto.',
            );
          }
          clip['assetId'] = await api.uploadFile(source);
          clip.remove('source');
        }
      }
      if (_cancelRequested) {
        yield const ExportProgress(
          phase: ExportPhase.cancelled,
          message: 'Esportazione annullata durante il caricamento.',
        );
        return;
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

      if (_cancelRequested) {
        await api.request('DELETE', '/v1/jobs/${Uri.encodeComponent(id)}');
        yield const ExportProgress(
          phase: ExportPhase.cancelled,
          message: 'Esportazione annullata.',
        );
        return;
      }

      while (_activeJobId == id && !_cancelRequested) {
        final status = await api.request('GET', '/v1/jobs/${Uri.encodeComponent(id)}');
        if (_cancelRequested) break;
        final state = (status['state'] ?? 'rendering').toString();
        final fraction = ((status['progress'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0);
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
            throw const FormatException(
              'Render completato ma il server non ha restituito downloadUrl.',
            );
          }
          await api.downloadFile(downloadUrl, request.outputPath);
          if (_cancelRequested) {
            final output = File(request.outputPath);
            if (await output.exists()) await output.delete();
            yield const ExportProgress(
              phase: ExportPhase.cancelled,
              message: 'Esportazione annullata durante il download.',
            );
            return;
          }
        }
        yield ExportProgress(
          phase: phase,
          fraction: fraction,
          message: status['message']?.toString() ?? '',
          outputPath: request.outputPath,
          error: status['error'],
        );
        if (phase == ExportPhase.completed ||
            phase == ExportPhase.failed ||
            phase == ExportPhase.cancelled) {
          return;
        }
        await Future<void>.delayed(pollInterval);
      }
      yield const ExportProgress(
        phase: ExportPhase.cancelled,
        message: 'Esportazione annullata.',
      );
    } finally {
      _activeJobId = null;
      _rendering = false;
      _cancelRequested = false;
    }
  }
}
