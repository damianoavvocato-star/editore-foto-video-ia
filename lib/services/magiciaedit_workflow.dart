import 'ai_processing_service.dart';
import '../models/magiciaedit_plan.dart';

class MagicIAeditException implements Exception {
  const MagicIAeditException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Coordinates a MagicIAedit request and turns the terminal backend result
/// into a validated plan that the user can review before applying.
class MagicIAeditWorkflow {
  const MagicIAeditWorkflow(this._service);

  final AiProcessingService _service;

  Future<MagicIAeditPlan> generate({
    required String jobId,
    required List<String> mediaPaths,
    Map<String, Object?> options = const {},
    void Function(AiJobProgress progress)? onProgress,
  }) async {
    final paths = List<String>.unmodifiable(mediaPaths);
    final request = AiTaskRequest(
      jobId: jobId,
      task: AiTaskKind.magicIAedit,
      inputPath: paths.isEmpty ? '' : paths.first,
      inputPaths: paths,
      options: options,
    );

    await for (final progress in _service.start(request)) {
      onProgress?.call(progress);
      switch (progress.state) {
        case AiJobState.succeeded:
          final result = progress.result;
          if (result == null) {
            throw const MagicIAeditException(
              'MagicIAedit ha terminato senza restituire un piano.',
            );
          }
          try {
            return MagicIAeditPlan.fromResult(result);
          } on FormatException catch (error) {
            throw MagicIAeditException(error.message);
          }
        case AiJobState.failed:
          final message = progress.message.trim().isNotEmpty
              ? progress.message
              : progress.error?.toString() ?? 'Elaborazione MagicIAedit non riuscita.';
          throw MagicIAeditException(message);
        case AiJobState.cancelled:
          throw const MagicIAeditException('Elaborazione MagicIAedit annullata.');
        case AiJobState.queued:
        case AiJobState.running:
          break;
      }
    }
    throw const MagicIAeditException(
      'Il servizio MagicIAedit si è chiuso senza un risultato finale.',
    );
  }

  Future<void> cancel(String jobId) => _service.cancel(jobId);
}
