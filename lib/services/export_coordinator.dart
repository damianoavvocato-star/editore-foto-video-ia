import 'dart:async';

import '../models/editor_project.dart';
import '../models/export_settings.dart';

enum ExportPhase { queued, preparing, rendering, finalizing, completed, failed, cancelled }

class ExportProgress {
  const ExportProgress({
    required this.phase,
    this.fraction = 0,
    this.message = '',
    this.outputPath,
    this.error,
  });

  final ExportPhase phase;
  final double fraction;
  final String message;
  final String? outputPath;
  final Object? error;

  bool get isTerminal =>
      phase == ExportPhase.completed ||
      phase == ExportPhase.failed ||
      phase == ExportPhase.cancelled;
}

class ExportRequest {
  const ExportRequest({
    required this.project,
    required this.settings,
    required this.outputPath,
  });

  final EditorProject project;
  final ExportSettings settings;
  final String outputPath;

  void validate() {
    if (outputPath.trim().isEmpty) {
      throw ArgumentError('Percorso di output mancante.');
    }
    if (project.tracks.length > 64) {
      throw StateError('Il progetto supera il limite di 64 tracce.');
    }
    if (project.fps < 1 || project.fps > 120) {
      throw RangeError.range(project.fps, 1, 120, 'project.fps');
    }
    if (project.width <= 0 || project.height <= 0 ||
        project.width > 7680 || project.height > 4320) {
      throw StateError('La risoluzione del progetto deve essere compresa tra 1×1 e 7680×4320.');
    }
    final trackIds = <String>{};
    for (final track in project.tracks) {
      if (track.id.trim().isEmpty || track.id != track.id.trim() ||
          !trackIds.add(track.id)) {
        throw StateError('Gli identificativi delle tracce devono essere presenti e univoci.');
      }
    }
    final clips = project.tracks.expand((track) => track.clips).toList();
    if (clips.isEmpty) {
      throw StateError('Aggiungi almeno una clip prima di esportare.');
    }
    if (clips.length > 500) {
      throw StateError('Il progetto supera il limite di 500 clip.');
    }
    final clipIds = <String>{};
    for (final clip in clips) {
      if (clip.id.trim().isEmpty || clip.id != clip.id.trim() ||
          !clipIds.add(clip.id)) {
        throw StateError('Gli identificativi delle clip devono essere presenti e univoci.');
      }
      if (clip.source.trim().isEmpty) {
        throw StateError('Una clip non contiene il percorso del file sorgente.');
      }
      if (clip.startMs < 0 ||
          clip.durationMs <= 0 ||
          !clip.speed.isFinite ||
          clip.speed <= 0 ||
          clip.transitionAfterMs < 0 ||
          clip.transitionAfterMs > clip.durationMs) {
        throw StateError('Una o più clip hanno parametri temporali o velocità non validi.');
      }
    }
    if (settings.framesPerSecond < 24 || settings.framesPerSecond > 120) {
      throw RangeError.range(settings.framesPerSecond, 24, 120, 'FPS');
    }
    if (settings.bitrateMbps < 1 || settings.bitrateMbps > 100) {
      throw RangeError.range(settings.bitrateMbps, 1, 100, 'bitrateMbps');
    }
  }
}

/// Contract for a native or platform-specific media renderer.
/// Implementations must emit progress and honor cancellation.
abstract interface class MediaRenderBackend {
  Stream<ExportProgress> render(ExportRequest request);
  Future<void> cancel();
}

/// Coordinates validation and forwards backend progress to UI listeners.
/// No actual encoder is bundled in this starter; inject a renderer implementation.
class ExportCoordinator {
  ExportCoordinator(this.backend);

  final MediaRenderBackend backend;
  StreamController<ExportProgress>? _active;
  StreamSubscription<ExportProgress>? _activeSubscription;

  Stream<ExportProgress> start(ExportRequest request) {
    if (_active != null && !_active!.isClosed) {
      throw StateError('Un’esportazione è già in corso.');
    }
    request.validate();
    final controller = StreamController<ExportProgress>();
    _active = controller;
    controller.add(const ExportProgress(
      phase: ExportPhase.preparing,
      fraction: 0,
      message: 'Preparazione progetto…',
    ));

    late StreamSubscription<ExportProgress> subscription;
    late Stream<ExportProgress> renderStream;
    try {
      // Some platform backends can fail before returning a stream (for example,
      // when a native plugin is unavailable). Do not leave the coordinator
      // permanently marked as busy in that case.
      renderStream = backend.render(request);
    } catch (error) {
      controller.add(ExportProgress(
        phase: ExportPhase.failed,
        message: 'Impossibile avviare il motore di esportazione',
        error: error,
      ));
      controller.close();
      _active = null;
      return controller.stream;
    }
    var terminalProgressReceived = false;
    subscription = renderStream.listen(
      (progress) {
        if (progress.isTerminal) terminalProgressReceived = true;
        if (!controller.isClosed) controller.add(progress);
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) {
          controller.add(ExportProgress(
            phase: ExportPhase.failed,
            message: 'Esportazione non riuscita',
            error: error,
          ));
          controller.close();
        }
        _active = null;
        _activeSubscription = null;
      },
      onDone: () {
        // A renderer must explicitly report completion, failure, or cancellation.
        // A stream that simply closes is not proof that an output file is valid.
        if (!terminalProgressReceived && !controller.isClosed) {
          controller.add(const ExportProgress(
            phase: ExportPhase.failed,
            message: 'Il motore di esportazione si è fermato senza comunicare un esito.',
          ));
        }
        if (!controller.isClosed) controller.close();
        _active = null;
        _activeSubscription = null;
      },
      cancelOnError: false,
    );
    _activeSubscription = subscription;
    controller.onCancel = () async {
      await subscription.cancel();
      _active = null;
      _activeSubscription = null;
    };
    return controller.stream;
  }

  Future<void> cancel() async {
    final controller = _active;
    if (controller == null || controller.isClosed) return;

    Object? cancellationError;
    try {
      await backend.cancel();
    } catch (error) {
      cancellationError = error;
    }

    // Stop listening to the renderer as well as asking the native backend to
    // stop. Otherwise a renderer that ignores cancellation can keep working
    // and emit stale progress after the UI has moved on.
    await _activeSubscription?.cancel();
    if (!controller.isClosed) {
      controller.add(ExportProgress(
        phase: cancellationError == null ? ExportPhase.cancelled : ExportPhase.failed,
        message: cancellationError == null
            ? 'Esportazione annullata.'
            : 'Errore durante l’annullamento dell’esportazione.',
        error: cancellationError,
      ));
      await controller.close();
    }
    _active = null;
    _activeSubscription = null;
  }
}
