import 'dart:convert';

enum MediaKind { video, image, audio, text }

MediaKind _mediaKindFromJson(Object? value) {
  for (final kind in MediaKind.values) {
    if (kind.name == value) return kind;
  }
  throw FormatException('Tipo di contenuto multimediale non supportato: $value');
}

class EditorClip {
  const EditorClip({
    required this.id,
    required this.source,
    required this.kind,
    required this.startMs,
    required this.durationMs,
    this.title = '',
    this.speed = 1,
    this.transitionAfterMs = 0,
    this.transitionAfter = 'fade',
  });

  final String id;
  final String source;
  final MediaKind kind;
  final int startMs;
  final int durationMs;
  final String title;
  final double speed;
  /// Transition applied after this clip when joining the next clip.
  final int transitionAfterMs;
  final String transitionAfter;

  int get endMs => startMs + durationMs;

  EditorClip copyWith({
    int? startMs,
    int? durationMs,
    String? title,
    double? speed,
    int? transitionAfterMs,
    String? transitionAfter,
  }) =>
      EditorClip(
        id: id,
        source: source,
        kind: kind,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        title: title ?? this.title,
        speed: speed ?? this.speed,
        transitionAfterMs: transitionAfterMs ?? this.transitionAfterMs,
        transitionAfter: transitionAfter ?? this.transitionAfter,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        'kind': kind.name,
        'startMs': startMs,
        'durationMs': durationMs,
        'title': title,
        'speed': speed,
        'transitionAfterMs': transitionAfterMs,
        'transitionAfter': transitionAfter,
      };

  factory EditorClip.fromJson(Map<String, dynamic> json) => EditorClip(
        id: json['id'] as String,
        source: json['source'] as String,
        kind: _mediaKindFromJson(json['kind']),
        startMs: json['startMs'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 3000,
        title: json['title'] as String? ?? '',
        speed: (json['speed'] as num?)?.toDouble() ?? 1,
        transitionAfterMs: json['transitionAfterMs'] as int? ?? 0,
        transitionAfter: json['transitionAfter'] as String? ?? 'fade',
      );
}

class EditorTrack {
  const EditorTrack({
    required this.id,
    required this.name,
    required this.kind,
    this.clips = const [],
    this.muted = false,
    this.locked = false,
  });

  final String id;
  final String name;
  final MediaKind kind;
  final List<EditorClip> clips;
  final bool muted;
  final bool locked;

  EditorTrack copyWith({
    List<EditorClip>? clips,
    bool? muted,
    bool? locked,
  }) =>
      EditorTrack(
        id: id,
        name: name,
        kind: kind,
        clips: clips ?? this.clips,
        muted: muted ?? this.muted,
        locked: locked ?? this.locked,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'muted': muted,
        'locked': locked,
        'clips': clips.map((clip) => clip.toJson()).toList(),
      };

  factory EditorTrack.fromJson(Map<String, dynamic> json) => EditorTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: _mediaKindFromJson(json['kind']),
        muted: json['muted'] as bool? ?? false,
        locked: json['locked'] as bool? ?? false,
        clips: (json['clips'] as List<dynamic>? ?? [])
            .map((clip) => EditorClip.fromJson(clip as Map<String, dynamic>))
            .toList(),
      );
}

class EditorProject {
  const EditorProject({
    required this.id,
    required this.name,
    this.width = 1080,
    this.height = 1920,
    this.fps = 30,
    this.tracks = const [],
  });

  final String id;
  final String name;
  final int width;
  final int height;
  final int fps;
  final List<EditorTrack> tracks;

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'name': name,
        'width': width,
        'height': height,
        'fps': fps,
        'tracks': tracks.map((track) => track.toJson()).toList(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory EditorProject.fromJson(Map<String, dynamic> json) {
    // Files without a version are legacy v1 projects. Never silently open a
    // future schema with fields or semantics this editor may not understand.
    final schemaVersion = json['schemaVersion'] ?? 1;
    if (schemaVersion is! int || schemaVersion != 1) {
      throw FormatException('Versione progetto non supportata: $schemaVersion');
    }
    return EditorProject(
        id: json['id'] as String,
        name: json['name'] as String,
        width: json['width'] as int? ?? 1080,
        height: json['height'] as int? ?? 1920,
        fps: json['fps'] as int? ?? 30,
        tracks: (json['tracks'] as List<dynamic>? ?? [])
            .map((track) => EditorTrack.fromJson(track as Map<String, dynamic>))
            .toList(),
      );
  }
}
