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
  ClipColorGrade? _draftColorGrade;
  KeyframeProperty _keyframeProperty = KeyframeProperty.scale;
  double _keyframeValue = 1;

  static const Map<String, Map<String, String>> _translations = {
    'it': {
      'timeline': 'Timeline', 'undo': 'Annulla', 'redo': 'Ripeti', 'split': 'Dividi al cursore',
      'duplicate': 'Duplica', 'delete': 'Elimina', 'rippleDelete': 'Elimina e chiudi spazio', 'unmute': 'Riattiva audio',
      'mute': 'Silenzia traccia', 'unlock': 'Sblocca traccia',
      'lock': 'Blocca traccia', 'clip': 'Clip', 'duration': 'Durata',
      'speed': 'Velocità', 'nextTransition': 'Transizione successiva',
      'fade': 'Dissolvenza', 'wipeLeft': 'Tendina sinistra',
      'wipeRight': 'Tendina destra', 'slideLeft': 'Scorrimento sinistra',
      'slideRight': 'Scorrimento destra', 'dissolve': 'Dissolvenza incrociata',
      'transitionDuration': 'Durata transizione',
      'select': 'Seleziona una clip per modificarne durata e velocità.',
      'locked': 'Traccia bloccata: sbloccarla per modificare la clip.',
      'color': 'Regolazione colore', 'exposure': 'Esposizione', 'contrast': 'Contrasto',
      'saturation': 'Saturazione', 'temperature': 'Temperatura', 'tint': 'Tinta',
      'highlights': 'Luci', 'shadows': 'Ombre', 'reset': 'Ripristina',
    },
    'en': {
      'timeline': 'Timeline', 'undo': 'Undo', 'redo': 'Redo', 'split': 'Split at playhead',
      'duplicate': 'Duplicate', 'delete': 'Delete', 'rippleDelete': 'Delete and close gap', 'unmute': 'Unmute track',
      'mute': 'Mute track', 'unlock': 'Unlock track', 'lock': 'Lock track',
      'clip': 'Clip', 'duration': 'Duration', 'speed': 'Speed',
      'nextTransition': 'Next transition', 'fade': 'Fade',
      'wipeLeft': 'Wipe left', 'wipeRight': 'Wipe right',
      'slideLeft': 'Slide left', 'slideRight': 'Slide right',
      'dissolve': 'Cross dissolve', 'transitionDuration': 'Transition duration',
      'select': 'Select a clip to change its duration and speed.',
      'locked': 'Track locked: unlock it to edit this clip.',
      'color': 'Color grading', 'exposure': 'Exposure', 'contrast': 'Contrast',
      'saturation': 'Saturation', 'temperature': 'Temperature', 'tint': 'Tint',
      'highlights': 'Highlights', 'shadows': 'Shadows', 'reset': 'Reset',
    },
    'fr': {
      'timeline': 'Chronologie', 'undo': 'Annuler', 'redo': 'Rétablir', 'split': 'Couper à la tête de lecture',
      'duplicate': 'Dupliquer', 'delete': 'Supprimer', 'rippleDelete': 'Supprimer et fermer l’espace', 'unmute': 'Réactiver le son',
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
      'duplicate': 'Duplicar', 'delete': 'Eliminar', 'rippleDelete': 'Eliminar y cerrar espacio', 'unmute': 'Activar sonido',
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
      'duplicate': 'تكرار', 'delete': 'حذف', 'rippleDelete': 'حذف وإغلاق الفراغ', 'unmute': 'إلغاء كتم المسار',
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
      _draftColorGrade = null;
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

  Widget _buildColorGradePanel(
    BuildContext context,
    ClipColorGrade grade,
    bool locked,
  ) {
    final theme = Theme.of(context);
    Widget slider(String key, double value, double min, double max, {
      int divisions = 100,
      String? suffix,
    }) => Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(children: [
        SizedBox(width: 104, child: Text(_t(key), style: theme.textTheme.bodySmall)),
        Expanded(child: Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max).toDouble(),
          onChanged: locked ? null : (next) => setState(() {
            _draftColorGrade = _copyGrade(grade, key, next);
          }),
          onChangeEnd: locked ? null : (next) {
            _session.setSelectedColorGrade(_copyGrade(grade, key, next));
            setState(() => _draftColorGrade = null);
          },
        )),
        SizedBox(
          width: 42,
          child: Text(
            '${value.toStringAsFixed(1)}${suffix ?? ''}',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ]),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        leading: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8D69F4), Color(0xFF2D9DAB)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.palette_outlined, color: Colors.white, size: 18),
        ),
        title: Text(_t('color'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${_t('exposure')} ${grade.exposure.toStringAsFixed(1)} · ${_t('saturation')} ${grade.saturation.toStringAsFixed(1)}',
          style: theme.textTheme.labelSmall,
        ),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: locked ? null : () {
                _session.setSelectedColorGrade(const ClipColorGrade());
                setState(() => _draftColorGrade = null);
              },
              icon: const Icon(Icons.restart_alt, size: 16),
              label: Text(_t('reset')),
            ),
          ),
          slider('exposure', grade.exposure, -5, 5),
          slider('contrast', grade.contrast, 0, 2),
          slider('saturation', grade.saturation, 0, 2),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              widget.languageCode == 'it' ? 'Controlli avanzati' : 'Advanced controls',
              style: theme.textTheme.labelLarge,
            ),
            children: [
              slider('temperature', grade.temperature, -100, 100, divisions: 200),
              slider('tint', grade.tint, -100, 100, divisions: 200),
              slider('highlights', grade.highlights, -1, 1),
              slider('shadows', grade.shadows, -1, 1),
            ],
          ),
        ],
        ),
      ),
    );
  }


  Widget _buildKeyframePanel(EditorClip clip, bool locked) {
    final theme = Theme.of(context);
    final bounds = switch (_keyframeProperty) {
      KeyframeProperty.positionX || KeyframeProperty.positionY => (-1000.0, 1000.0),
      KeyframeProperty.scale => (0.1, 5.0),
      KeyframeProperty.rotation => (-180.0, 180.0),
      KeyframeProperty.opacity => (0.0, 1.0),
    };
    final relativeTime = (_session.playheadMs - clip.startMs)
        .clamp(0, clip.durationMs);
    final keyframes = [...clip.keyframes]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          leading: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2D9DAB), Color(0xFF8D69F4)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_motion, color: Colors.white, size: 18),
          ),
          title: Text(
            widget.languageCode == 'it' ? 'Animazione e keyframe' : 'Animation & keyframes',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${keyframes.length} · ${(relativeTime / 1000).toStringAsFixed(2)} s',
            style: theme.textTheme.labelSmall,
          ),
          children: [
            DropdownButtonFormField<KeyframeProperty>(
              initialValue: _keyframeProperty,
              decoration: InputDecoration(
                labelText: widget.languageCode == 'it' ? 'Proprietà animata' : 'Animated property',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: KeyframeProperty.values.map((property) {
                final label = switch (property) {
                  KeyframeProperty.positionX => 'Position X',
                  KeyframeProperty.positionY => 'Position Y',
                  KeyframeProperty.scale => 'Scale',
                  KeyframeProperty.rotation => 'Rotation',
                  KeyframeProperty.opacity => 'Opacity',
                };
                return DropdownMenuItem(value: property, child: Text(label));
              }).toList(),
              onChanged: locked ? null : (property) {
                if (property == null) return;
                setState(() {
                  _keyframeProperty = property;
                  _keyframeValue = switch (property) {
                    KeyframeProperty.scale || KeyframeProperty.opacity => 1,
                    _ => 0,
                  };
                });
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Slider(
                min: bounds.$1,
                max: bounds.$2,
                value: _keyframeValue.clamp(bounds.$1, bounds.$2).toDouble(),
                onChanged: locked ? null : (value) => setState(() => _keyframeValue = value),
              )),
              SizedBox(
                width: 58,
                child: Text(_keyframeValue.toStringAsFixed(2), textAlign: TextAlign.end),
              ),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: locked ? null : () => _session.setSelectedKeyframe(
                  EditorKeyframe(
                    timeMs: relativeTime,
                    property: _keyframeProperty,
                    value: _keyframeValue,
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(widget.languageCode == 'it' ? 'Aggiungi / aggiorna al cursore' : 'Add / update at playhead'),
              ),
            ),
            if (keyframes.isNotEmpty) ...[
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.languageCode == 'it' ? 'Fotogrammi chiave' : 'Keyframes',
                  style: theme.textTheme.labelLarge),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: keyframes.map((keyframe) {
                  final label = '${keyframe.property.name} · ${(keyframe.timeMs / 1000).toStringAsFixed(2)}s';
                  return InputChip(
                    label: Text(label),
                    onDeleted: locked ? null : () => _session.removeSelectedKeyframe(
                      timeMs: keyframe.timeMs,
                      property: keyframe.property,
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              widget.languageCode == 'it'
                ? 'I valori sono salvati nel progetto; l’applicazione al rendering finale è ancora da completare.'
                : 'Values are saved in the project; applying them to final rendering is still pending.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  ClipColorGrade _copyGrade(ClipColorGrade source, String key, double value) =>
      ClipColorGrade(
        exposure: key == 'exposure' ? value : source.exposure,
        contrast: key == 'contrast' ? value : source.contrast,
        saturation: key == 'saturation' ? value : source.saturation,
        temperature: key == 'temperature' ? value : source.temperature,
        tint: key == 'tint' ? value : source.tint,
        highlights: key == 'highlights' ? value : source.highlights,
        shadows: key == 'shadows' ? value : source.shadows,
      );

  @override
  Widget build(BuildContext context) {
    final selected = _session.selectedClip;
    final visibleGrade = _draftColorGrade ?? selected?.colorGrade;
    final track = _session.selectedTrack;
    final locked = track?.locked ?? true;
    final transition = selected?.transitionAfter ?? 'fade';
    return Directionality(
      textDirection: widget.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: SingleChildScrollView(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelinePanel(
          tracks: _session.project.tracks,
          playheadMs: _session.playheadMs,
          onClipSelected: _session.selectClip,
          onPlayheadChanged: _session.setPlayhead,
          title: _t('timeline'),
          selectedClipId: _session.selectedClipId,
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
                      onPressed: selected == null || locked
                          ? null
                          : () => _session.deleteSelected(ripple: true),
                      icon: const Icon(Icons.content_cut_rounded),
                      label: Text(_t('rippleDelete')),
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
                if (selected != null && (selected.kind == MediaKind.video || selected.kind == MediaKind.image)) ...[
                  const SizedBox(height: 14),
                  _buildColorGradePanel(context, visibleGrade ?? selected.colorGrade, locked),
                  const SizedBox(height: 10),
                  _buildKeyframePanel(selected, locked),
                ],
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
        ),
      ),
    );
  }
}
