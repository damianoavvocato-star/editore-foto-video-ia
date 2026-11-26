import 'dart:async';

/// Small, dependency-free contract for a frame processing / AI effect provider.
/// A production implementation may use on-device ML, a licensed SDK, or a
/// remote service. Keep user consent, privacy and network state outside this API.
enum AiTaskKind {
  backgroundRemoval,
  imageEnhancement,
  videoEnhancement,
  autoCaptions,
  sceneDetection,
  smartCrop,
  magicIAedit,
}

enum AiJobState { queued, running, succeeded, failed, cancelled }

class AiJobProgress {
  const AiJobProgress({
    required this.jobId,
    required this.task,
    required this.state,
    this.fraction = 0,
    this.message = '',
    this.resultPath,
    this.error,
    this.result,
  });

  final String jobId;
  final AiTaskKind task;
  final AiJobState state;
  final double fraction;
  final String message;
  final String? resultPath;
  final Object? error;
  final Map<String, dynamic>? result;

  bool get isTerminal => state == AiJobState.succeeded ||
      state == AiJobState.failed ||
      state == AiJobState.cancelled;
}

class AiTaskRequest {
  const AiTaskRequest({
    required this.jobId,
    required this.task,
    required this.inputPath,
    this.inputPaths = const [],
    this.options = const {},
  });

  final String jobId;
  final AiTaskKind task;
  final String inputPath;
  final List<String> inputPaths;
  final Map<String, Object?> options;

  List<String> get mediaPaths => inputPaths.isEmpty ? [inputPath] : inputPaths;

  void validate() {
    if (jobId.trim().isEmpty) throw ArgumentError('jobId è obbligatorio.');
    if (mediaPaths.isEmpty || mediaPaths.any((path) => path.trim().isEmpty)) {
      throw ArgumentError('È richiesto almeno un percorso media valido.');
    }
    if (mediaPaths.length > 20) throw ArgumentError('MagicIAedit accetta al massimo 20 media.');
    if (options.keys.any((key) => key.trim().isEmpty)) {
      throw ArgumentError('Le chiavi delle opzioni non possono essere vuote.');
    }
  }
}

abstract interface class AiProcessingBackend {
  Stream<AiJobProgress> run(AiTaskRequest request);
  Future<void> cancel(String jobId);
}

/// AI orchestration seam: UI depends on this service, not on a specific provider.
class AiProcessingService {
  AiProcessingService(this.backend);

  final AiProcessingBackend backend;
  final Set<String> _activeJobs = {};

  Stream<AiJobProgress> start(AiTaskRequest request) {
    request.validate();
    if (!_activeJobs.add(request.jobId)) {
      throw StateError('Esiste già un job con ID ${request.jobId}.');
    }

    try {
      return backend.run(request).transform(
        StreamTransformer<AiJobProgress, AiJobProgress>.fromHandlers(
          handleData: (event, sink) {
            sink.add(event);
            if (event.isTerminal) _activeJobs.remove(request.jobId);
          },
          handleError: (error, stack, sink) {
            _activeJobs.remove(request.jobId);
            sink.addError(error, stack);
          },
          handleDone: (sink) {
            _activeJobs.remove(request.jobId);
            sink.close();
          },
        ),
      );
    } catch (_) {
      // A backend may throw before it can even return a stream (for example,
      // when its native channel is unavailable). Do not leave a phantom job.
      _activeJobs.remove(request.jobId);
      rethrow;
    }
  }

  Future<void> cancel(String jobId) async {
    if (!_activeJobs.contains(jobId)) return;
    await backend.cancel(jobId);
    _activeJobs.remove(jobId);
  }
}
