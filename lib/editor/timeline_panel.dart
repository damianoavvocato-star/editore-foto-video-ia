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
    this.selectedClipId,
  });

  final List<EditorTrack> tracks;
  final int playheadMs;
  final ValueChanged<EditorClip> onClipSelected;
  final ValueChanged<int> onPlayheadChanged;
  final String title;
  final String? selectedClipId;

  @override
  Widget build(BuildContext context) {
    final totalMs = tracks.expand((track) => track.clips)
        .fold<int>(6000, (max, clip) => clip.endMs > max ? clip.endMs : max);
    final safePlayhead = playheadMs.clamp(0, totalMs);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8D69F4), Color(0xFF397EAD)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.view_timeline_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${tracks.length} tracce · ${_formatTime(totalMs)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                ],
              )),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF30294C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x665F50A5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.circle, size: 7, color: Color(0xFFB7A5FF)),
                    const SizedBox(width: 6),
                    Text(_formatTime(safePlayhead), style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFFE6DEFF), fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.play_arrow_rounded, size: 17, color: muted),
              Expanded(child: Slider(
                min: 0, max: totalMs.toDouble(), value: safePlayhead.toDouble(),
                onChanged: (value) => onPlayheadChanged(value.round()),
              )),
              Icon(Icons.flag_outlined, size: 16, color: muted),
            ]),
            const SizedBox(height: 5),
            if (tracks.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.45)),
                ),
                child: Column(children: [
                  const Icon(Icons.add_to_photos_outlined, size: 30, color: Color(0xFF9B8CFF)),
                  const SizedBox(height: 9),
                  Text('Importa foto, video o audio per iniziare la timeline.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ]),
              )
            else ...[
              _TimeRuler(totalMs: totalMs),
              const SizedBox(height: 7),
              ...tracks.map((track) => _TrackRow(
                track: track, totalMs: totalMs, playheadMs: safePlayhead,
                onClipSelected: onClipSelected,
                selectedClipId: selectedClipId,
              )),
              const SizedBox(height: 9),
              const Wrap(spacing: 13, runSpacing: 6, children: [
                _LegendDot(color: Color(0xFF8068F1), label: 'Video'),
                _LegendDot(color: Color(0xFF20A89A), label: 'Foto'),
                _LegendDot(color: Color(0xFFE19A48), label: 'Audio'),
                _LegendDot(color: Color(0xFFD76A9A), label: 'Testo'),
                _LegendDot(color: Color(0xFFFFD76A), label: 'Keyframe'),
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
      const SizedBox(width: 94),
      Expanded(child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(5, (index) => Text(
          '${(totalMs * index / 4000).toStringAsFixed(0)}s',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        )),
      )),
    ]);
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.totalMs, required this.playheadMs, required this.onClipSelected, required this.selectedClipId});
  final EditorTrack track;
  final int totalMs;
  final int playheadMs;
  final ValueChanged<EditorClip> onClipSelected;
  final String? selectedClipId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labelWidth = 94.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: labelWidth, child: Row(children: [
          Container(
            width: 25, height: 25,
            decoration: BoxDecoration(
              color: _clipColor(track.kind).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_trackIcon(track.kind), size: 14, color: _clipColor(track.kind)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
        ])),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final timelineWidth = constraints.maxWidth < 460 ? 460.0 : constraints.maxWidth;
          final playheadX = timelineWidth * playheadMs / totalMs;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: timelineWidth, height: 52, child: Stack(children: [
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.45)),
              ))),
              for (var tick = 1; tick < 4; tick++)
                Positioned(left: timelineWidth * tick / 4, top: 0, bottom: 0,
                  child: Container(width: 1, color: theme.dividerColor.withValues(alpha: 0.45))),
              for (final clip in track.clips)
                for (final keyframe in clip.keyframes)
                  if (keyframe.timeMs >= 0 && keyframe.timeMs <= clip.durationMs)
                    Positioned(
                      left: (timelineWidth * (clip.startMs + keyframe.timeMs) / totalMs - 4)
                          .clamp(0, timelineWidth - 8),
                      top: 0,
                      child: const Icon(Icons.diamond, size: 9, color: Color(0xFFFFD76A)),
                    ),
              for (final clip in track.clips)
                Positioned(
                  left: timelineWidth * clip.startMs / totalMs,
                  width: (timelineWidth * clip.durationMs / totalMs).clamp(36, timelineWidth),
                  top: 4, bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [_clipColor(clip.kind), Color.lerp(_clipColor(clip.kind), Colors.black, 0.28)!],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedClipId == clip.id ? Colors.white : Colors.white.withValues(alpha: 0.22),
                        width: selectedClipId == clip.id ? 2 : 0.8,
                      ),
                      boxShadow: selectedClipId == clip.id
                          ? [BoxShadow(color: _clipColor(clip.kind).withValues(alpha: 0.38), blurRadius: 9)]
                          : const [],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onClipSelected(clip),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  clip.title.isEmpty ? clip.kind.name : clip.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                ),
                              )),
                              Row(children: [
                                Icon(_clipIcon(clip.kind), size: 10, color: Colors.white70),
                                const SizedBox(width: 4),
                                Expanded(child: Text(
                                  '${(clip.durationMs / 1000).toStringAsFixed(1)} s',
                                  maxLines: 1,
                                  style: const TextStyle(color: Colors.white70, fontSize: 9),
                                )),
                                if (clip.keyframes.isNotEmpty)
                                  const Icon(Icons.auto_awesome, size: 10, color: Color(0xFFFFE08A)),
                                if (clip.colorGrade.exposure != 0 || clip.colorGrade.contrast != 1 || clip.colorGrade.saturation != 1)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 3),
                                    child: Icon(Icons.tune, size: 10, color: Colors.white),
                                  ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(left: playheadX.clamp(0, timelineWidth), top: 0, bottom: 0,
                child: Column(children: [
                  Container(width: 9, height: 9, decoration: const BoxDecoration(
                    color: Color(0xFFFF647C), shape: BoxShape.circle,
                  )),
                  Expanded(child: Container(width: 2, color: const Color(0xFFFF647C))),
                ]),
              ),
            ])),
          );
        })),
      ]),
    );
  }

  static IconData _trackIcon(MediaKind kind) => switch (kind) {
    MediaKind.video => Icons.movie_outlined,
    MediaKind.image => Icons.image_outlined,
    MediaKind.audio => Icons.graphic_eq,
    MediaKind.text => Icons.title,
  };

  static IconData _clipIcon(MediaKind kind) => _trackIcon(kind);

  static Color _clipColor(MediaKind kind) => switch (kind) {
    MediaKind.video => const Color(0xFF8068F1),
    MediaKind.image => const Color(0xFF20A89A),
    MediaKind.audio => const Color(0xFFE19A48),
    MediaKind.text => const Color(0xFFD76A9A),
  };
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: Theme.of(context).textTheme.labelSmall),
  ]);
}
