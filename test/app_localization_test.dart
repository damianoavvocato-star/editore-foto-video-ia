import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/main.dart';

void main() {
  test('Arabic uses RTL and the other supported languages use LTR', () {
    expect(textDirectionForLanguage(AppLanguage.ar), TextDirection.rtl);
    expect(textDirectionForLanguage(AppLanguage.it), TextDirection.ltr);
    expect(textDirectionForLanguage(AppLanguage.en), TextDirection.ltr);
    expect(textDirectionForLanguage(AppLanguage.fr), TextDirection.ltr);
    expect(textDirectionForLanguage(AppLanguage.es), TextDirection.ltr);
  });
}
