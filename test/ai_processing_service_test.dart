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

  test('MagicIAedit accepts a bounded list of media paths', () {
    const request = AiTaskRequest(
      jobId: 'magic-1',
      task: AiTaskKind.magicIAedit,
      inputPath: '',
      inputPaths: ['/tmp/one.jpg', '/tmp/two.mp4'],
    );
    expect(request.validate, returnsNormally);
    expect(request.mediaPaths, hasLength(2));
  });

  test('MagicIAedit rejects more than twenty media paths', () {
    final request = AiTaskRequest(
      jobId: 'magic-2',
      task: AiTaskKind.magicIAedit,
      inputPath: '/tmp/one.jpg',
      inputPaths: List<String>.generate(21, (index) => '/tmp/$index.jpg'),
    );
    expect(request.validate, throwsA(isA<ArgumentError>()));
  });

}
