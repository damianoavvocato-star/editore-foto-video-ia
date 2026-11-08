enum ExportContainer { mp4, mov, avi, webm }

enum ExportResolution { p720, p1080, p1440, p2160 }

enum ExportCodec { h264, h265, vp9 }

class ExportSettings {
  const ExportSettings({
    this.container = ExportContainer.mp4,
    this.resolution = ExportResolution.p1080,
    this.codec = ExportCodec.h264,
    this.framesPerSecond = 30,
    this.includeAudio = true,
    this.bitrateMbps = 12,
  });

  final ExportContainer container;
  final ExportResolution resolution;
  final ExportCodec codec;
  final int framesPerSecond;
  final bool includeAudio;
  final int bitrateMbps;

  int get width => switch (resolution) {
        ExportResolution.p720 => 1280,
        ExportResolution.p1080 => 1920,
        ExportResolution.p1440 => 2560,
        ExportResolution.p2160 => 3840,
      };

  int get height => switch (resolution) {
        ExportResolution.p720 => 720,
        ExportResolution.p1080 => 1080,
        ExportResolution.p1440 => 1440,
        ExportResolution.p2160 => 2160,
      };

  ExportSettings copyWith({
    ExportContainer? container,
    ExportResolution? resolution,
    ExportCodec? codec,
    int? framesPerSecond,
    bool? includeAudio,
    int? bitrateMbps,
  }) =>
      ExportSettings(
        container: container ?? this.container,
        resolution: resolution ?? this.resolution,
        codec: codec ?? this.codec,
        framesPerSecond: (framesPerSecond ?? this.framesPerSecond).clamp(24, 120),
        includeAudio: includeAudio ?? this.includeAudio,
        bitrateMbps: (bitrateMbps ?? this.bitrateMbps).clamp(1, 100),
      );
}
