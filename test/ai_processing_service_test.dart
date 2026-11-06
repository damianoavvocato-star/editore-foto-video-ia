import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:editore_foto_video_ia/services/ai_processing_service.dart';
import 'package:editore_foto_video_ia/services/smart_shield_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('SmartShield adaptive performance policy', () {
    const policy = SmartShieldPolicy();

    test('waits for enough measured frames', () {
      expect(policy.evaluate(measuredFrames: 10, slowFrames: 10,
        current: SmartShieldMode.balanced), SmartShieldMode.balanced);
    });

    test('switches to conservative mode under sustained jank', () {
      expect(policy.evaluate(measuredFrames: 60, slowFrames: 18,
        current: SmartShieldMode.balanced), SmartShieldMode.conservative);
    });

    test('recovers only after frame pacing is healthy', () {
      expect(policy.evaluate(measuredFrames: 60, slowFrames: 2,
        current: SmartShieldMode.conservative), SmartShieldMode.balanced);
    });

    test('hysteresis prevents profile oscillation', () {
      expect(policy.evaluate(measuredFrames: 60, slowFrames: 9,
        current: SmartShieldMode.conservative), SmartShieldMode.conservative);
    });

    test('conservative mode reduces preview image decode workload', () {
      expect(policy.previewDecodeScale(SmartShieldMode.balanced), 1.0);
      expect(policy.previewDecodeScale(SmartShieldMode.conservative), 0.65);
    });

    test('manager follows app background and resume lifecycle', () {
      final manager = SmartShieldManager();
      var notifications = 0;
      manager.addListener(() => notifications++);
      manager.start();
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(manager.isInBackground, isTrue);
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(notifications, 1);
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(manager.isInBackground, isFalse);
      expect(notifications, 2);
      manager.dispose();
      manager.dispose();
    });

    test('manager bounds the frame sample window', () {
      final manager = SmartShieldManager(maxFrameSamples: 1);
      expect(manager.maxFrameSamples, 30);
      manager.dispose();
    });

    test('manager rejects a non-positive frame threshold', () {
      expect(
        () => SmartShieldManager(slowFrameThreshold: Duration.zero),
        throwsArgumentError,
      );
    });

    test('manager cannot be restarted after disposal', () {
      final manager = SmartShieldManager();
      manager.dispose();
      expect(manager.start, throwsStateError);
    });
  });

}
