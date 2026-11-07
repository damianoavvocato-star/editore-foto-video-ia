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
    this.languageCode = 'it',
  });

  final EditorProject project;
  final ValueChanged<EditorProject>? onProjectChanged;
  final String languageCode;

  @override
  State<SessionTimelineEditor> createState() => _SessionTimelineEditorState();
}

class _SessionTimelineEditorState extends State<SessionTimelineEditor> {
  late EditorSession _session;

  static const Map<String, Map<String, String>> _translations = {
    'it': {
      'timeline': 'Timeline', 'undo': 'Annulla', 'redo': 'Ripeti', 'split': 'Dividi al cursore',
      'duplicate': 'Duplica', 'delete': 'Elimina', 'unmute': 'Riattiva audio',
      'mute': 'Silenzia traccia', 'unlock': 'Sblocca traccia',
      'lock': 'Blocca traccia', 'clip': 'Clip', 'duration': 'Durata',
      'speed': 'Velocità', 'nextTransition': 'Transizione successiva',
      'fade': 'Dissolvenza', 'wipeLeft': 'Tendina sinistra',
      'wipeRight': 'Tendina destra', 'slideLeft': 'Scorrimento sinistra',
      'slideRight': 'Scorrimento destra', 'dissolve': 'Dissolvenza incrociata',
      'transitionDuration': 'Durata transizione',
      'select': 'Seleziona una clip per modificarne durata e velocità.',
      'locked': 'Traccia bloccata: sbloccarla per modificare la clip.',
    },
    'en': {
      'timeline': 'Timeline', 'undo': 'Undo', 'redo': 'Redo', 'split': 'Split at playhead',
      'duplicate': 'Duplicate', 'delete': 'Delete', 'unmute': 'Unmute track',
      'mute': 'Mute track', 'unlock': 'Unlock track', 'lock': 'Lock track',
      'clip': 'Clip', 'duration': 'Duration', 'speed': 'Speed',
      'nextTransition': 'Next transition', 'fade': 'Fade',
      'wipeLeft': 'Wipe left', 'wipeRight': 'Wipe right',
      'slideLeft': 'Slide left', 'slideRight': 'Slide right',
      'dissolve': 'Cross dissolve', 'transitionDuration': 'Transition duration',
      'select': 'Select a clip to change its duration and speed.',
      'locked': 'Track locked: unlock it to edit this clip.',
    },
    'fr': {
      'timeline': 'Chronologie', 'undo': 'Annuler', 'redo': 'Rétablir', 'split': 'Couper à la tête de lecture',
      'duplicate': 'Dupliquer', 'delete': 'Supprimer', 'unmute': 'Réactiver le son',
      'mute': 'Couper le son', 'unlock': 'Déverrouiller la piste',
      'lock': 'Verrouiller la piste', 'clip': 'Clip', 'duration': 'Durée',
      'speed': 'Vitesse', 'nextTransition': 'Transition suivante',
      'fade': 'Fondu', 'wipeLeft': 'Balayage gauche',
      'wipeRight': 'Balayage droite', 'slideLeft': 'Glissement gauche',
      'slideRight': 'Glissement droite', 'dissolve': 'Fondu enchaîné',
      'transitionDuration': 'Durée de transition',
      'select': 'Sélectionnez un clip pour modifier sa durée et sa vitesse.',
      'locked': 'Piste verrouillée : déverrouillez-la pour modifier ce clip.',
    },
    'es': {
      'timeline': 'Línea de tiempo', 'undo': 'Deshacer', 'redo': 'Rehacer', 'split': 'Dividir en el cursor',
      'duplicate': 'Duplicar', 'delete': 'Eliminar', 'unmute': 'Activar sonido',
      'mute': 'Silenciar pista', 'unlock': 'Desbloquear pista',
      'lock': 'Bloquear pista', 'clip': 'Clip', 'duration': 'Duración',
      'speed': 'Velocidad', 'nextTransition': 'Transición siguiente',
      'fade': 'Fundido', 'wipeLeft': 'Barrido izquierda',
      'wipeRight': 'Barrido derecha', 'slideLeft': 'Deslizar izquierda',
      'slideRight': 'Deslizar derecha', 'dissolve': 'Disolución cruzada',
      'transitionDuration': 'Duración de transición',
      'select': 'Selecciona un clip para cambiar su duración y velocidad.',
      'locked': 'Pista bloqueada: desbloquéala para editar este clip.',
    },
    'ar': {
      'timeline': 'الخط الزمني', 'undo': 'تراجع', 'redo': 'إعادة', 'split': 'تقسيم عند مؤشر التشغيل',
      'duplicate': 'تكرار', 'delete': 'حذف', 'unmute': 'إلغاء كتم المسار',
      'mute': 'كتم المسار', 'unlock': 'إلغاء قفل المسار',
      'lock': 'قفل المسار', 'clip': 'مقطع', 'duration': 'المدة',
      'speed': 'السرعة', 'nextTransition': 'الانتقال التالي',
      'fade': 'تلاشي', 'wipeLeft': 'مسح لليسار',
      'wipeRight': 'مسح لليمين', 'slideLeft': 'انزلاق لليسار',
      'slideRight': 'انزلاق لليمين', 'dissolve': 'تلاشي متداخل',
      'transitionDuration': 'مدة الانتقال',
      'select': 'اختر مقطعاً لتغيير مدته وسرعته.',
      'locked': 'المسار مقفل: ألغِ قفله لتعديل هذا المقطع.',
    },
  };

  String _t(String key) =>
      _translations[widget.languageCode]?[key] ?? _translations['en']![key]!;

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
          title: _t('timeline'),
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
                      label: Text(_t('undo')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _session.canRedo ? _session.redo : null,
                      icon: const Icon(Icons.redo),
                      label: Text(_t('redo')),
                    ),
                    FilledButton.icon(
                      onPressed: selected == null || locked ? null : _session.splitSelected,
                      icon: const Icon(Icons.content_cut),
                      label: Text(_t('split')),
                    ),
                    OutlinedButton.icon(
                      onPressed: selected == null || locked ? null : _session.duplicateSelected,
                      icon: const Icon(Icons.copy),
                      label: Text(_t('duplicate')),
                    ),
                    OutlinedButton.icon(
                      onPressed: selected == null || locked ? null : () => _session.deleteSelected(),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(_t('delete')),
                    ),
                    OutlinedButton.icon(
                      onPressed: track == null ? null : _session.toggleSelectedTrackMuted,
                      icon: Icon(track?.muted == true ? Icons.volume_off : Icons.volume_up),
                      label: Text(_t(track?.muted == true ? 'unmute' : 'mute')),
                    ),
                    OutlinedButton.icon(
                      onPressed: track == null ? null : _session.toggleSelectedTrackLocked,
                      icon: Icon(track?.locked == true ? Icons.lock_open : Icons.lock),
                      label: Text(_t(track?.locked == true ? 'unlock' : 'lock')),
                    ),
                  ],
                ),
                if (selected != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${_t('clip')}: ${selected.title.isEmpty ? selected.kind.name : selected.title}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text('${_t('duration')}: ${(selected.durationMs / 1000).toStringAsFixed(2)} s'),
                  Slider(
                    min: 500,
                    max: 60000,
                    divisions: 119,
                    value: selected.durationMs.clamp(500, 60000).toDouble(),
                    onChanged: locked ? null : (value) => _session.trimSelected(value.round()),
                  ),
                  Row(
                    children: [
                      Text(_t('speed')),
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
                      Text(_t('nextTransition')),
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
                        items: [
                          DropdownMenuItem(value: 'fade', child: Text(_t('fade'))),
                          DropdownMenuItem(value: 'wipeleft', child: Text(_t('wipeLeft'))),
                          DropdownMenuItem(value: 'wiperight', child: Text(_t('wipeRight'))),
                          DropdownMenuItem(value: 'slideleft', child: Text(_t('slideLeft'))),
                          DropdownMenuItem(value: 'slideright', child: Text(_t('slideRight'))),
                          DropdownMenuItem(value: 'dissolve', child: Text(_t('dissolve'))),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(_t('transitionDuration')),
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
                  if (track?.locked == true) Text(_t('locked')),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_t('select')),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
