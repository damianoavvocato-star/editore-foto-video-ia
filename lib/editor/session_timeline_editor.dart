import 'package:flutter/material.dart';

import '../models/editor_project.dart';
import '../state/editor_session.dart';
import 'timeline_panel.dart';

/// Connects timeline gestures and clip operations to an EditorSession.
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
    final track = _session.selectedTrack;
    final locked = track?.locked ?? true;
    final transition = selected?.transitionAfter ?? 'fade';
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
                      onPressed: selected == null || locked ? null : _session.splitSelected,
                      icon: const Icon(Icons.content_cut),
                      label: const Text('Dividi al cursore'),
                    ),
                    OutlinedButton.icon(
                      onPressed: selected == null || locked ? null : _session.duplicateSelected,
                      icon: const Icon(Icons.copy),
                      label: const Text('Duplica'),
                    ),
                    OutlinedButton.icon(
                      onPressed: selected == null || locked ? null : () => _session.deleteSelected(),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Elimina'),
                    ),
                    OutlinedButton.icon(
                      onPressed: track == null ? null : _session.toggleSelectedTrackMuted,
                      icon: Icon(track?.muted == true ? Icons.volume_off : Icons.volume_up),
                      label: Text(track?.muted == true ? 'Riattiva audio' : 'Silenzia traccia'),
                    ),
                    OutlinedButton.icon(
                      onPressed: track == null ? null : _session.toggleSelectedTrackLocked,
                      icon: Icon(track?.locked == true ? Icons.lock_open : Icons.lock),
                      label: Text(track?.locked == true ? 'Sblocca traccia' : 'Blocca traccia'),
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
                    onChanged: locked ? null : (value) => _session.trimSelected(value.round()),
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
                          onChanged: locked ? null : _session.setSelectedSpeed,
                        ),
                      ),
                      Text('${selected.speed.toStringAsFixed(2)}×'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      const Text('Transizione successiva'),
                      DropdownButton<String>(
                        value: const ['fade', 'wipeleft', 'wiperight', 'slideleft', 'slideright', 'dissolve']
                                .contains(transition) ? transition : 'fade',
                        onChanged: locked ? null : (value) {
                          if (value != null) {
                            _session.setSelectedTransition(
                              type: value, durationMs: selected.transitionAfterMs,
                            );
                          }
                        },
                        items: const [
                          DropdownMenuItem(value: 'fade', child: Text('Dissolvenza')),
                          DropdownMenuItem(value: 'wipeleft', child: Text('Tendina sinistra')),
                          DropdownMenuItem(value: 'wiperight', child: Text('Tendina destra')),
                          DropdownMenuItem(value: 'slideleft', child: Text('Scorrimento sinistra')),
                          DropdownMenuItem(value: 'slideright', child: Text('Scorrimento destra')),
                          DropdownMenuItem(value: 'dissolve', child: Text('Dissolvenza incrociata')),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Durata transizione'),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 3000,
                          divisions: 30,
                          value: selected.transitionAfterMs.clamp(0, 3000).toDouble(),
                          onChanged: locked ? null : (value) => _session.setSelectedTransition(
                            type: transition, durationMs: value.round(),
                          ),
                        ),
                      ),
                      Text('${(selected.transitionAfterMs / 1000).toStringAsFixed(1)} s'),
                    ],
                  ),
                  if (track?.locked == true)
                    const Text('Traccia bloccata: sbloccarla per modificare la clip.'),
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
