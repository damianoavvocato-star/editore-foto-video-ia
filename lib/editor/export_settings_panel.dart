import 'package:flutter/material.dart';
import '../models/export_settings.dart';

/// UI for selecting output properties. A renderer should consume the returned
/// ExportSettings; this widget intentionally does not claim to encode media.
class ExportSettingsPanel extends StatefulWidget {
  const ExportSettingsPanel({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final ExportSettings initial;
  final ValueChanged<ExportSettings> onChanged;

  @override
  State<ExportSettingsPanel> createState() => _ExportSettingsPanelState();
}

class _ExportSettingsPanelState extends State<ExportSettingsPanel> {
  late ExportSettings settings;

  @override
  void initState() {
    super.initState();
    settings = widget.initial;
  }

  void update(ExportSettings value) {
    setState(() => settings = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Impostazioni esportazione',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<ExportContainer>(
              value: settings.container,
              decoration: const InputDecoration(labelText: 'Formato contenitore'),
              items: ExportContainer.values
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.name.toUpperCase())))
                  .toList(),
              onChanged: (v) {
                if (v != null) update(settings.copyWith(container: v));
              },
            ),
            DropdownButtonFormField<ExportResolution>(
              value: settings.resolution,
              decoration: const InputDecoration(labelText: 'Risoluzione'),
              items: ExportResolution.values
                  .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text('${settingsLabel(v)} (${_dimensions(v)})'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) update(settings.copyWith(resolution: v));
              },
            ),
            DropdownButtonFormField<ExportCodec>(
              value: settings.codec,
              decoration: const InputDecoration(labelText: 'Codec'),
              items: ExportCodec.values
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.name.toUpperCase())))
                  .toList(),
              onChanged: (v) {
                if (v != null) update(settings.copyWith(codec: v));
              },
            ),
            const SizedBox(height: 8),
            Text('Frame rate: ${settings.framesPerSecond} FPS'),
            Slider(
              min: 24,
              max: 120,
              divisions: 96,
              value: settings.framesPerSecond.toDouble(),
              onChanged: (v) => update(settings.copyWith(framesPerSecond: v.round())),
            ),
            Text('Bitrate: ${settings.bitrateMbps} Mbps'),
            Slider(
              min: 1,
              max: 100,
              divisions: 99,
              value: settings.bitrateMbps.toDouble(),
              onChanged: (v) => update(settings.copyWith(bitrateMbps: v.round())),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Includi audio'),
              value: settings.includeAudio,
              onChanged: (v) => update(settings.copyWith(includeAudio: v)),
            ),
          ],
        ),
      ),
    );
  }

  String _dimensions(ExportResolution value) => switch (value) {
        ExportResolution.p720 => '1280×720',
        ExportResolution.p1080 => '1920×1080',
        ExportResolution.p1440 => '2560×1440',
        ExportResolution.p2160 => '3840×2160',
      };

  String settingsLabel(ExportResolution value) => switch (value) {
        ExportResolution.p720 => '720p',
        ExportResolution.p1080 => '1080p',
        ExportResolution.p1440 => '1440p',
        ExportResolution.p2160 => '4K',
      };
}
