import 'package:flutter/foundation.dart';

import '../editor/editing_operations.dart';
import '../models/editor_project.dart';

/// Change-notifying editing session with bounded undo/redo history.
class EditorSession extends ChangeNotifier {
  EditorSession(
    EditorProject initial, {
    EditingOperations operations = const EditingOperations(),
    this.historyLimit = 60,
  })  : _project = initial,
        _operations = operations;

  EditorProject _project;
  final EditingOperations _operations;
  final int historyLimit;
  final List<EditorProject> _undo = [];
  final List<EditorProject> _redo = [];
  String? _selectedClipId;
  int _playheadMs = 0;

  EditorProject get project => _project;
  String? get selectedClipId => _selectedClipId;
  int get playheadMs => _playheadMs;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  EditorClip? get selectedClip {
    final id = _selectedClipId;
    if (id == null) return null;
    for (final track in _project.tracks) {
      for (final clip in track.clips) {
        if (clip.id == id) return clip;
      }
    }
    return null;
  }

  EditorTrack? get selectedTrack {
    final id = _selectedClipId;
    if (id == null) return null;
    for (final track in _project.tracks) {
      if (track.clips.any((clip) => clip.id == id)) return track;
    }
    return null;
  }

  void replaceProject(EditorProject project, {bool clearHistory = true}) {
    if (_same(project, _project)) return;
    _project = project;
    _selectedClipId = null;
    _playheadMs = 0;
    if (clearHistory) {
      _undo.clear();
      _redo.clear();
    }
    notifyListeners();
  }

  void selectClip(EditorClip clip) {
    _selectedClipId = clip.id;
    _playheadMs = clip.startMs;
    notifyListeners();
  }

  void setPlayhead(int milliseconds) {
    final total = _project.tracks
        .expand((track) => track.clips)
        .fold<int>(0, (max, clip) => clip.endMs > max ? clip.endMs : max);
    _playheadMs = milliseconds.clamp(0, total).toInt();
    notifyListeners();
  }

  void moveSelected(int startMs) {
    final clip = selectedClip;
    final track = selectedTrack;
    if (clip == null || track == null || track.locked) return;
    _commit(_operations.moveClip(
      project: _project, trackId: track.id, clipId: clip.id, newStartMs: startMs,
    ));
  }

  void trimSelected(int durationMs, {int? startMs}) {
    final clip = selectedClip;
    final track = selectedTrack;
    if (clip == null || track == null || track.locked) return;
    _commit(_operations.trimClip(
      project: _project, trackId: track.id, clipId: clip.id,
      durationMs: durationMs, newStartMs: startMs,
    ));
  }

  void splitSelected() {
    final clip = selectedClip;
    final track = selectedTrack;
    if (clip == null || track == null || track.locked) return;
    final splitTime = _playheadMs;
    if (splitTime <= clip.startMs || splitTime >= clip.endMs) return;
    _commit(_operations.splitClip(
      project: _project, trackId: track.id, clipId: clip.id,
      splitAtMs: splitTime, newClipId: _uniqueClipId('split'),
    ));
  }

  void duplicateSelected() {
    final clip = selectedClip;
    final track = selectedTrack;
    if (clip == null || track == null || track.locked) return;
    final id = _uniqueClipId('copy');
    final next = _operations.duplicateClip(
      project: _project, trackId: track.id, clipId: clip.id,
      newClipId: id, offsetMs: clip.durationMs,
    );
    if (_same(next, _project)) return;
    _selectedClipId = id;
    _playheadMs = next.tracks
        .expand((item) => item.clips)
        .firstWhere((item) => item.id == id).startMs;
    _commit(next);
  }

  void deleteSelected({bool ripple = false}) {
    final clip = selectedClip;
    final track = selectedTrack;
    if (clip == null || track == null || track.locked) return;
    final next = _operations.deleteClip(
      project: _project, trackId: track.id, clipId: clip.id, ripple: ripple,
    );
    if (_same(next, _project)) return;
    _selectedClipId = null;
    _commit(next);
  }

  void setSelectedTransition({required String type, required int durationMs}) {
    final clip = selectedClip;
    final track = selectedTrack;
    if (clip == null || track == null || track.locked) return;
    _commit(_operations.setTransitionAfter(
      project: _project, trackId: track.id, clipId: clip.id,
      type: type, durationMs: durationMs,
    ));
  }

  void toggleSelectedTrackMuted() {
    final track = selectedTrack;
    if (track == null) return;
    _commit(_operations.setTrackMuted(
      project: _project, trackId: track.id, muted: !track.muted,
    ));
  }

  void toggleSelectedTrackLocked() {
    final track = selectedTrack;
    if (track == null) return;
    _commit(_operations.setTrackLocked(
      project: _project, trackId: track.id, locked: !track.locked,
    ));
  }

  void setSelectedSpeed(double speed) {
    final clip = selectedClip;
    final track = selectedTrack;
    if (clip == null || track == null || track.locked) return;
    _commit(_operations.setClipSpeed(
      project: _project, trackId: track.id, clipId: clip.id, speed: speed,
    ));
  }

  String _uniqueClipId(String suffix) {
    final existing = _project.tracks
        .expand((track) => track.clips)
        .map((clip) => clip.id)
        .toSet();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var candidate = '${_selectedClipId ?? 'clip'}_${suffix}_$stamp';
    var counter = 0;
    while (existing.contains(candidate)) {
      counter++;
      candidate = '${_selectedClipId ?? 'clip'}_${suffix}_$stamp_$counter';
    }
    return candidate;
  }

  void _commit(EditorProject next) {
    if (identical(next, _project) || _same(next, _project)) return;
    _undo.add(_project);
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    _project = next;
    notifyListeners();
  }

  bool _same(EditorProject a, EditorProject b) => a.encode() == b.encode();

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_project);
    _project = _undo.removeLast();
    if (_selectedClipId != null && selectedClip == null) _selectedClipId = null;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_project);
    _project = _redo.removeLast();
    if (_selectedClipId != null && selectedClip == null) _selectedClipId = null;
    notifyListeners();
  }
}
