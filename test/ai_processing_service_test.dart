import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/services/ai_processing_service.dart';

void main() {
  test('AI task rejects blank input', () {
    const request = AiTaskRequest(
      jobId: 'job-1',
      task: AiTaskKind.smartCrop,
      inputPath: ' ',
    );
    expect(request.validate, throwsA(isA<ArgumentError>()));
  });

  test('AI task rejects blank job identifier', () {
    const request = AiTaskRequest(
      jobId: ' ',
      task: AiTaskKind.imageEnhancement,
      inputPath: '/tmp/photo.jpg',
    );
    expect(request.validate, throwsA(isA<ArgumentError>()));
  });
}
