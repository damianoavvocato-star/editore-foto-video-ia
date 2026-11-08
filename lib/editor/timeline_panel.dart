import 'package:flutter/material.dart';
import '../models/editor_project.dart';

/// Responsive multi-track timeline with a time ruler, selectable clips and playhead.
class TimelinePanel extends StatelessWidget {
  const TimelinePanel({
    super.key,
    required this.tracks,
    required this.playheadMs,
    required this.onClipSelected,
    required this.onPlayheadChanged,
    this.title = 'Timeline',
  });

  final List<EditorTrack> tracks;
  final int playheadMs;
  final ValueChanged<EditorClip> onClipSelected;
  final ValueChanged<int> onPlayheadChanged;
  final String title;

  @override
  Widget build(BuildContext context) {
    final totalMs = tracks.expand((track) => track.clips)
        .fold<int>(6000, (max, clip) => clip.endMs > max ? clip.endMs : max);
    final safePlayhead = playheadMs.clamp(0, totalMs);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.view_timeline, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              DecoratedBox(
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(_formatTime(safePlayhead), style: theme.textTheme.labelLarge),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Slider(
              min: 0, max: totalMs.toDouble(), value: safePlayhead.toDouble(),
              onChanged: (value) => onPlayheadChanged(value.round()),
            ),
            const SizedBox(height: 4),
            if (tracks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(children: [
                  Icon(Icons.add_to_photos_outlined, size: 28, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text('Importa foto, video o audio per iniziare la timeline.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              )
            else ...[
              _TimeRuler(totalMs: totalMs),
              const SizedBox(height: 6),
              ...tracks.map((track) => _TrackRow(
                track: track, totalMs: totalMs, playheadMs: safePlayhead,
                onClipSelected: onClipSelected,
              )),
              const SizedBox(height: 4),
              const Wrap(spacing: 12, runSpacing: 4, children: [
                _LegendDot(color: Color(0xFF6554D9), label: 'Video'),
                _LegendDot(color: Color(0xFF168A82), label: 'Foto'),
                _LegendDot(color: Color(0xFFBA6C22), label: 'Audio'),
                _LegendDot(color: Color(0xFFB04470), label: 'Testo'),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTime(int milliseconds) => '${(milliseconds / 1000).toStringAsFixed(1)} s';
}

class _TimeRuler extends StatelessWidget {
  const _TimeRuler({required this.totalMs});
  final int totalMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      const SizedBox(width: 82),
      Expanded(child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(5, (index) => Text(
          '${(totalMs * index / 4000).toStringAsFixed(0)}s',
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        )),
      )),
    ]);
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.totalMs, required this.playheadMs, required this.onClipSelected});
  final EditorTrack track;
  final int totalMs;
  final int playheadMs;
  final ValueChanged<EditorClip> onClipSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = 420.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 82, child: Row(children: [
          Icon(_trackIcon(track.kind), size: 15, color: _clipColor(track.kind)),
          const SizedBox(width: 5),
          Expanded(child: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
        ])),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final timelineWidth = constraints.maxWidth < width ? width : constraints.maxWidth;
          final playheadX = timelineWidth * playheadMs / totalMs;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: timelineWidth, height: 46, child: Stack(children: [
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
              ))),
              for (final clip in track.clips)
                Positioned(
                  left: timelineWidth * clip.startMs / totalMs,
                  width: (timelineWidth * clip.durationMs / totalMs).clamp(34, timelineWidth),
                  top: 4, bottom: 4,
                  child: Material(
                    color: _clipColor(clip.kind),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onClipSelected(clip),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Align(alignment: Alignment.centerLeft, child: Text(
                          clip.title.isEmpty ? clip.kind.name : clip.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        )),
                      ),
                    ),
                  ),
                ),
              Positioned(left: playheadX.clamp(0, timelineWidth), top: 0, bottom: 0,
                child: Container(width: 2, color: theme.colorScheme.tertiary)),
            ])),
          );
        })),
      ]),
    );
  }

  IconData _trackIcon(MediaKind kind) => switch (kind) {
    MediaKind.video => Icons.movie_outlined,
    MediaKind.image => Icons.image_outlined,
    MediaKind.audio => Icons.graphic_eq,
    MediaKind.text => Icons.title,
  };

  Color _clipColor(MediaKind kind) => switch (kind) {
    MediaKind.video => const Color(0xFF6554D9),
    MediaKind.image => const Color(0xFF168A82),
    MediaKind.audio => const Color(0xFFBA6C22),
    MediaKind.text => const Color(0xFFB04470),
  };
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: Theme.of(context).textTheme.labelSmall),
  ]);
}
