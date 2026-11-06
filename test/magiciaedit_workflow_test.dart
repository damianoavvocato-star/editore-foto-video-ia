import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/magiciaedit_plan.dart';
import 'package:editore_foto_video_ia/services/ai_processing_service.dart';
import 'package:editore_foto_video_ia/services/magiciaedit_workflow.dart';

class _FakeAiBackend implements AiProcessingBackend {
  _FakeAiBackend(this.updates);

  final List<AiJobProgress> updates;
  AiTaskRequest? lastRequest;
  String? cancelledJob;

  @override
  Stream<AiJobProgress> run(AiTaskRequest request) async* {
    lastRequest = request;
    yield* Stream<AiJobProgress>.fromIterable(updates);
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelledJob = jobId;
  }
}

void main() {
  test('workflow returns a validated plan and reports progress', () async {
    final backend = _FakeAiBackend([
      const AiJobProgress(
        jobId: 'magic-job',
        task: AiTaskKind.magicIAedit,
        state: AiJobState.running,
        fraction: 0.5,
        message: 'Analisi in corso',
      ),
      const AiJobProgress(
        jobId: 'magic-job',
        task: AiTaskKind.magicIAedit,
        state: AiJobState.succeeded,
        fraction: 1,
        result: {
          'title': 'Montaggio IA',
          'durationMs': 3000,
          'sourcePaths': {'asset-1': '/media/clip.mp4'},
          'clips': [
            {
              'assetId': 'asset-1',
              'sourceStartMs': 500,
              'durationMs': 3000,
              'startMs': 0,
              'transitionAfterMs': 0,
              'transitionAfter': 'fade',
              'reason': 'Scena iniziale',
            },
          ],
        },
      ),
    ]);
    final workflow = MagicIAeditWorkflow(AiProcessingService(backend));
    final progress = <AiJobProgress>[];

    final plan = await workflow.generate(
      jobId: 'magic-job',
      mediaPaths: ['/media/clip.mp4'],
      onProgress: progress.add,
    );

    expect(plan, isA<MagicIAeditPlan>());
    expect(plan.title, 'Montaggio IA');
    expect(plan.clips.single.sourceStartMs, 500);
    expect(backend.lastRequest?.task, AiTaskKind.magicIAedit);
    expect(backend.lastRequest?.mediaPaths, ['/media/clip.mp4']);
    expect(progress, hasLength(2));
  });

  test('workflow reports a backend failure safely', () async {
    final backend = _FakeAiBackend([
      const AiJobProgress(
        jobId: 'magic-failed',
        task: AiTaskKind.magicIAedit,
        state: AiJobState.failed,
        message: 'Provider non disponibile.',
      ),
    ]);
    final workflow = MagicIAeditWorkflow(AiProcessingService(backend));

    await expectLater(
      workflow.generate(
        jobId: 'magic-failed',
        mediaPaths: ['/media/clip.mp4'],
      ),
      throwsA(isA<MagicIAeditException>()),
    );
  });

  test('workflow reports cancellation and delegates cancel requests', () async {
    final backend = _FakeAiBackend([
      const AiJobProgress(
        jobId: 'magic-cancel',
        task: AiTaskKind.magicIAedit,
        state: AiJobState.cancelled,
      ),
    ]);
    final workflow = MagicIAeditWorkflow(AiProcessingService(backend));

    await expectLater(
      workflow.generate(
        jobId: 'magic-cancel',
        mediaPaths: ['/media/clip.mp4'],
      ),
      throwsA(isA<MagicIAeditException>()),
    );
    await workflow.cancel('another-job');
    expect(backend.cancelledJob, 'another-job');
  });

  test('workflow rejects a successful response without a valid plan', () async {
    final backend = _FakeAiBackend([
      const AiJobProgress(
        jobId: 'magic-invalid',
        task: AiTaskKind.magicIAedit,
        state: AiJobState.succeeded,
        result: {'clips': []},
      ),
    ]);
    final workflow = MagicIAeditWorkflow(AiProcessingService(backend));

    await expectLater(
      workflow.generate(
        jobId: 'magic-invalid',
        mediaPaths: ['/media/clip.mp4'],
      ),
      throwsA(isA<MagicIAeditException>()),
    );
  });
}
