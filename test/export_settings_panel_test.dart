import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/editor/export_settings_panel.dart';
import 'package:editore_foto_video_ia/models/export_settings.dart';

void main() {
  testWidgets('export panel summarizes the selected output profile', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExportSettingsPanel(
          initial: const ExportSettings(
            container: ExportContainer.mov,
            resolution: ExportResolution.p2160,
            framesPerSecond: 60,
          ),
          onChanged: (_) {},
        ),
      ),
    ));

    expect(find.textContaining('MOV · 4K · 60 FPS'), findsOneWidget);
    expect(find.textContaining('3840 × 2160'), findsOneWidget);
    expect(find.text('Codec video'), findsOneWidget);
    expect(find.text('Includi audio'), findsOneWidget);
  });

  testWidgets('panel refreshes when the parent supplies new settings', (tester) async {
    Widget buildPanel(ExportSettings settings) => MaterialApp(
      home: Scaffold(
        body: ExportSettingsPanel(initial: settings, onChanged: (_) {}),
      ),
    );

    await tester.pumpWidget(buildPanel(const ExportSettings()));
    expect(find.textContaining('MP4 · 1080p · 30 FPS'), findsOneWidget);

    await tester.pumpWidget(buildPanel(const ExportSettings(
      container: ExportContainer.webm,
      resolution: ExportResolution.p1440,
      framesPerSecond: 50,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('WEBM · 1440p · 50 FPS'), findsOneWidget);
    expect(find.textContaining('2560 × 1440'), findsOneWidget);
  });

  testWidgets('changing audio preference notifies the parent', (tester) async {
    ExportSettings? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExportSettingsPanel(
          initial: const ExportSettings(),
          onChanged: (value) => changed = value,
        ),
      ),
    ));

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed!.includeAudio, isFalse);
  });
}
