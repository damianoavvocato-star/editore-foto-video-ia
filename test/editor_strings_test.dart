import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:editore_foto_video_ia/l10n/editor_strings.dart';

void main() {
  test('localization has fallback and Arabic direction', () {
    expect(const EditorStrings(Locale('it')).text('export'), 'Esporta');
    expect(const EditorStrings(Locale('ar')).textDirection, TextDirection.rtl);
    expect(const EditorStrings(Locale('de')).text('export'), 'Export');
  });
}
