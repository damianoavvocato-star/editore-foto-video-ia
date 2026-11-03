import 'package:flutter/material.dart';
import '../models/editor_project.dart';

/// A first timeline UI: selectable clips and playhead display.
/// Rendering, drag-to-reorder and waveform extraction are intentionally separate
/// engine tasks so the UI does not pretend to export media yet.
class TimelinePanel extends StatelessWidget {
  const TimelinePanel({
    super.key,
    required this.tracks,
    required this.playheadMs,
    required this.onClipSelected,
    required this.onPlayheadChanged,
  });

  final List<EditorTrack> tracks;
  final int playheadMs;
  final ValueChanged<EditorClip> onClipSelected;
  final ValueChanged<int> onPlayheadChanged;

  @override
  Widget build(BuildContext context) {
    final totalMs = tracks
        .expand((track) => track.clips)
        .fold<int>(6000, (max, clip) => clip.endMs > max ? clip.endMs : max);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.view_timeline),
                const SizedBox(width: 8),
                Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${(playheadMs / 1000).toStringAsFixed(1)} s'),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              min: 0,
              max: totalMs.toDouble(),
              value: playheadMs.clamp(0, totalMs).toDouble(),
              onChanged: (value) => onPlayheadChanged(value.round()),
            ),
            const SizedBox(height: 4),
            ...tracks.map((track) => _TrackRow(
                  track: track,
                  totalMs: totalMs,
                  onClipSelected: onClipSelected,
                )),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.totalMs,
    required this.onClipSelected,
  });

  final EditorTrack track;
  final int totalMs;
  final ValueChanged<EditorClip> onClipSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: 38,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      for (final clip in track.clips)
                        Positioned(
                          left: constraints.maxWidth * clip.startMs / totalMs,
                          width: (constraints.maxWidth * clip.durationMs / totalMs)
                              .clamp(24, constraints.maxWidth),
                          top: 3,
                          bottom: 3,
                          child: Material(
                            color: _clipColor(clip.kind),
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              onTap: () => onClipSelected(clip),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    clip.title.isEmpty ? clip.kind.name : clip.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _clipColor(MediaKind kind) => switch (kind) {
        MediaKind.video => const Color(0xFF6554D9),
        MediaKind.image => const Color(0xFF168A82),
        MediaKind.audio => const Color(0xFFBA6C22),
        MediaKind.text => const Color(0xFFB04470),
      };
}
