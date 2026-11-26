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

  @override
  void didUpdateWidget(covariant ExportSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      settings = widget.initial;
    }
  }

  void update(ExportSettings value) {
    setState(() => settings = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final fieldWidth = width < 520 ? double.infinity : 250.0;

    return SingleChildScrollView(
      child: Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8068F1), Color(0xFF28A99B)],
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.high_quality_outlined,
                      color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Impostazioni esportazione',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 3),
                      Text(
                        'Personalizza formato, risoluzione e qualità del file.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant
                      .withValues(alpha: 0.6),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.movie_creation_outlined, size: 18),
                  Text(
                    '${settings.container.name.toUpperCase()} · ${settingsLabel(settings.resolution)} · ${settings.framesPerSecond} FPS',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    '${settings.width} × ${settings.height}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('Formato e dimensioni', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<ExportContainer>(
                    initialValue: settings.container,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Formato contenitore',
                      prefixIcon: Icon(Icons.video_file_outlined),
                    ),
                    items: ExportContainer.values
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.name.toUpperCase()),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) update(settings.copyWith(container: v));
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<ExportResolution>(
                    initialValue: settings.resolution,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Risoluzione',
                      prefixIcon: Icon(Icons.aspect_ratio_outlined),
                    ),
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
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<ExportCodec>(
                    initialValue: settings.codec,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Codec video',
                      prefixIcon: Icon(Icons.settings_outlined),
                    ),
                    items: ExportCodec.values
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.name.toUpperCase()),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) update(settings.copyWith(codec: v));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Qualità video', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _QualitySlider(
              title: 'Frame rate',
              value: settings.framesPerSecond.toDouble(),
              valueLabel: '${settings.framesPerSecond} FPS',
              min: 24,
              max: 120,
              divisions: 96,
              onChanged: (v) => update(
                settings.copyWith(framesPerSecond: v.round()),
              ),
            ),
            const SizedBox(height: 8),
            _QualitySlider(
              title: 'Bitrate',
              value: settings.bitrateMbps.toDouble(),
              valueLabel: '${settings.bitrateMbps} Mbps',
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (v) => update(
                settings.copyWith(bitrateMbps: v.round()),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('Includi audio'),
              subtitle: const Text('Mantieni la traccia audio nel file finale'),
              value: settings.includeAudio,
              onChanged: (v) => update(settings.copyWith(includeAudio: v)),
            ),
            const SizedBox(height: 8),
            Text(
              'Queste sono preferenze di esportazione: la codifica effettiva '
              'dipende dal motore di rendering collegato.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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

class _QualitySlider extends StatelessWidget {
  const _QualitySlider({
    required this.title,
    required this.value,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final double value;
  final String valueLabel;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.labelLarge),
            ),
            Text(
              valueLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max).toDouble(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
