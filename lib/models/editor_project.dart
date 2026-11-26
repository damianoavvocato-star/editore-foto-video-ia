import 'dart:convert';

enum MediaKind { video, image, audio, text }

/// Animatable clip properties stored in project-local timeline time.
enum KeyframeProperty { positionX, positionY, scale, rotation, opacity }

class EditorKeyframe {
  const EditorKeyframe({
    required this.timeMs,
    required this.property,
    required this.value,
  }) : assert(timeMs >= 0);

  final int timeMs;
  final KeyframeProperty property;
  final double value;

  Map<String, Object?> toJson() => {
        'timeMs': timeMs,
        'property': property.name,
        'value': value,
      };

  factory EditorKeyframe.fromJson(Map<String, dynamic> json) {
    final propertyName = json['property'];
    final property = KeyframeProperty.values.where(
      (candidate) => candidate.name == propertyName,
    );
    final rawValue = json['value'];
    final rawTime = json['timeMs'];
    if (property.isEmpty || rawTime is! int || rawTime < 0 ||
        rawValue is! num || !rawValue.toDouble().isFinite) {
      throw const FormatException('Fotogramma chiave non valido.');
    }
    return EditorKeyframe(
      timeMs: rawTime,
      property: property.first,
      value: rawValue.toDouble(),
    );
  }
}

MediaKind _mediaKindFromJson(Object? value) {
  for (final kind in MediaKind.values) {
    if (kind.name == value) return kind;
  }
  throw FormatException('Tipo di contenuto multimediale non supportato: $value');
}

/// Per-clip color controls persisted with the editable project.
class ClipColorGrade {
  const ClipColorGrade({
    this.exposure = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.temperature = 0,
    this.tint = 0,
    this.highlights = 0,
    this.shadows = 0,
  });

  final double exposure;
  final double contrast;
  final double saturation;
  final double temperature;
  final double tint;
  final double highlights;
  final double shadows;

  Map<String, Object?> toJson() => {
        'exposure': exposure,
        'contrast': contrast,
        'saturation': saturation,
        'temperature': temperature,
        'tint': tint,
        'highlights': highlights,
        'shadows': shadows,
      };

  factory ClipColorGrade.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback, double min, double max) {
      final raw = json[key];
      if (raw == null) return fallback;
      if (raw is! num || !raw.toDouble().isFinite ||
          raw.toDouble() < min || raw.toDouble() > max) {
        throw FormatException('Valore colore non valido: $key');
      }
      return raw.toDouble();
    }

    return ClipColorGrade(
      exposure: read('exposure', 0, -5, 5),
      contrast: read('contrast', 1, 0, 2),
      saturation: read('saturation', 1, 0, 2),
      temperature: read('temperature', 0, -100, 100),
      tint: read('tint', 0, -100, 100),
      highlights: read('highlights', 0, -1, 1),
      shadows: read('shadows', 0, -1, 1),
    );
  }
}

class EditorClip {
  const EditorClip({
    required this.id,
    required this.source,
    required this.kind,
    required this.startMs,
    required this.durationMs,
    this.sourceStartMs = 0,
    this.title = '',
    this.speed = 1,
    this.transitionAfterMs = 0,
    this.transitionAfter = 'fade',
    this.keyframes = const [],
    this.colorGrade = const ClipColorGrade(),
  });

  final String id;
  final String source;
  final MediaKind kind;
  final int startMs;
  final int durationMs;
  /// Offset within the original source file, distinct from timeline startMs.
  final int sourceStartMs;
  final String title;
  final double speed;
  /// Transition applied after this clip when joining the next clip.
  final int transitionAfterMs;
  final String transitionAfter;
  /// Property animation points, expressed relative to this clip's start.
  final List<EditorKeyframe> keyframes;
  final ClipColorGrade colorGrade;

  int get endMs => startMs + durationMs;

  EditorClip copyWith({
    int? startMs,
    int? durationMs,
    int? sourceStartMs,
    String? title,
    double? speed,
    int? transitionAfterMs,
    String? transitionAfter,
    List<EditorKeyframe>? keyframes,
    ClipColorGrade? colorGrade,
  }) =>
      EditorClip(
        id: id,
        source: source,
        kind: kind,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        sourceStartMs: sourceStartMs ?? this.sourceStartMs,
        title: title ?? this.title,
        speed: speed ?? this.speed,
        transitionAfterMs: transitionAfterMs ?? this.transitionAfterMs,
        transitionAfter: transitionAfter ?? this.transitionAfter,
        keyframes: keyframes ?? this.keyframes,
        colorGrade: colorGrade ?? this.colorGrade,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        'kind': kind.name,
        'startMs': startMs,
        'durationMs': durationMs,
        'sourceStartMs': sourceStartMs,
        'title': title,
        'speed': speed,
        'transitionAfterMs': transitionAfterMs,
        'transitionAfter': transitionAfter,
        'keyframes': keyframes.map((keyframe) => keyframe.toJson()).toList(),
        'colorGrade': colorGrade.toJson(),
      };

  factory EditorClip.fromJson(Map<String, dynamic> json) => EditorClip(
        id: json['id'] as String,
        source: json['source'] as String,
        kind: _mediaKindFromJson(json['kind']),
        startMs: json['startMs'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 3000,
        sourceStartMs: json['sourceStartMs'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        speed: (json['speed'] as num?)?.toDouble() ?? 1,
        transitionAfterMs: json['transitionAfterMs'] as int? ?? 0,
        transitionAfter: json['transitionAfter'] as String? ?? 'fade',
        keyframes: (json['keyframes'] as List<dynamic>? ?? [])
            .map((item) => EditorKeyframe.fromJson(item as Map<String, dynamic>))
            .toList(),
        colorGrade: json['colorGrade'] == null
            ? const ClipColorGrade()
            : ClipColorGrade.fromJson(
                json['colorGrade'] as Map<String, dynamic>,
              ),
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

  EditorProject copyWith({
    String? id,
    String? name,
    int? width,
    int? height,
    int? fps,
    List<EditorTrack>? tracks,
  }) =>
      EditorProject(
        id: id ?? this.id,
        name: name ?? this.name,
        width: width ?? this.width,
        height: height ?? this.height,
        fps: fps ?? this.fps,
        tracks: tracks ?? this.tracks,
      );

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
