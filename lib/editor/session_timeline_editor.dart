import 'package:flutter/material.dart';

import '../models/editor_project.dart';
import '../state/editor_session.dart';
import 'timeline_panel.dart';

/// Connects timeline gestures and basic clip operations to an EditorSession.
/// The parent may persist the emitted project with ProjectStore.
class SessionTimelineEditor extends StatefulWidget {
  const SessionTimelineEditor({
    super.key,
    required this.project,
    this.onProjectChanged,
  });

  final EditorProject project;
  final ValueChanged<EditorProject>? onProjectChanged;

  @override
  State<SessionTimelineEditor> createState() => _SessionTimelineEditorState();
}

class _SessionTimelineEditorState extends State<SessionTimelineEditor> {
  late EditorSession _session;

  @override
  void initState() {
    super.initState();
    _session = EditorSession(widget.project)..addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant SessionTimelineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.encode() != widget.project.encode()) {
      _session.replaceProject(widget.project);
    }
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
    widget.onProjectChanged?.call(_session.project);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _session.selectedClip;
    final locked = _session.selectedTrack?.locked ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelinePanel(
          tracks: _session.project.tracks,
          playheadMs: _session.playheadMs,
          onClipSelected: _session.selectClip,
          onPlayheadChanged: _session.setPlayhead,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _session.canUndo ? _session.undo : null,
                      icon: const Icon(Icons.undo),
                      label: const Text('Annulla'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _session.canRedo ? _session.redo : null,
                      icon: const Icon(Icons.redo),
                      label: const Text('Ripeti'),
                    ),
                    FilledButton.icon(
                      onPressed: selected == null || locked
                          ? null
                          : _session.splitSelected,
                      icon: const Icon(Icons.content_cut),
                      label: const Text('Dividi al cursore'),
                    ),
                  ],
                ),
                if (selected != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Clip: ${selected.title.isEmpty ? selected.kind.name : selected.title}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text('Durata: ${(selected.durationMs / 1000).toStringAsFixed(2)} s'),
                  Slider(
                    min: 500,
                    max: 60000,
                    divisions: 119,
                    value: selected.durationMs.clamp(500, 60000).toDouble(),
                    onChanged: locked
                        ? null
                        : (value) => _session.trimSelected(value.round()),
                  ),
                  Row(
                    children: [
                      const Text('Velocità'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Slider(
                          min: 0.25,
                          max: 4,
                          divisions: 15,
                          value: selected.speed.clamp(0.25, 4).toDouble(),
                          onChanged: locked
                              ? null
                              : _session.setSelectedSpeed,
                        ),
                      ),
                      Text('${selected.speed.toStringAsFixed(2)}×'),
                    ],
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Seleziona una clip per modificarne durata e velocità.'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
