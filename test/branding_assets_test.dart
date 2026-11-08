import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MagicIAedit launcher and splash branding assets are configured', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final appIcon = File('assets/branding/app_icon.svg').readAsStringSync();
    final mark = File('assets/branding/magiciaedit_mark.svg').readAsStringSync();
    final appSource = File('lib/main.dart').readAsStringSync();

    expect(pubspec, contains('image_path: assets/branding/app_icon.png'));
    expect(pubspec, contains('adaptive_icon_foreground: assets/branding/app_icon_foreground.png'));
    expect(pubspec, contains('image: assets/branding/splash_logo.png'));
    expect(pubspec, contains('assets/branding/magiciaedit_mark.svg'));
    expect(appIcon, contains('>I</text>'));
    expect(appIcon, contains('>A</text>'));
    expect(appIcon, contains('linearGradient'));
    expect(mark, contains('>I</text>'));
    expect(mark, contains('>A</text>'));
    expect(appSource, contains("title: 'MagicIAedit – AI Photo & Video Studio'"));
    expect(appSource, contains("'app': 'MagicIAedit'"));
  });
}
