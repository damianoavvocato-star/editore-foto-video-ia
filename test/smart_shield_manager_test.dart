import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/services/smart_shield_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('memory pressure immediately selects conservative preview mode', () {
    final manager = SmartShieldManager();
    var notifications = 0;
    manager.addListener(() => notifications++);

    manager.didHaveMemoryPressure();

    expect(manager.mode, SmartShieldMode.conservative);
    expect(manager.previewDecodeScale, 0.65);
    expect(manager.measuredFrames, 0);
    expect(notifications, 1);

    manager.dispose();
  });

  test('repeated memory pressure does not emit redundant notifications', () {
    final manager = SmartShieldManager();
    var notifications = 0;
    manager.addListener(() => notifications++);

    manager.didHaveMemoryPressure();
    manager.didHaveMemoryPressure();

    expect(manager.mode, SmartShieldMode.conservative);
    expect(notifications, 1);

    manager.dispose();
  });

  test('memory pressure after disposal is safely ignored', () {
    final manager = SmartShieldManager();
    manager.dispose();

    expect(manager.didHaveMemoryPressure, returnsNormally);
    expect(manager.mode, SmartShieldMode.balanced);
  });
}
