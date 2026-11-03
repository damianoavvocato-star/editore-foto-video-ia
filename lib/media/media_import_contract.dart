/// Tipologia rilevata durante l'importazione, distinta dal modello timeline.
enum MediaKind { video, image, audio, unknown }

/// Metadati minimi e indipendenti dal plugin usato per selezionare i file.
class ImportedMediaAsset {
  const ImportedMediaAsset({
    required this.id,
    required this.path,
    required this.kind,
    this.durationSeconds,
    this.mimeType,
    this.fileSizeBytes,
  });

  final String id;
  final String path;
  final MediaKind kind;
  final double? durationSeconds;
  final String? mimeType;
  final int? fileSizeBytes;
}

/// Returns a human-readable validation error, or null when metadata is usable.
/// This checks metadata only; it does not claim that the file exists or decodes.
String? validateImportedMediaAsset(ImportedMediaAsset asset) {
  if (asset.id.trim().isEmpty) return 'ID del file mancante.';
  if (asset.path.trim().isEmpty) return 'Percorso del file mancante.';
  if (asset.kind == MediaKind.unknown) return 'Formato multimediale non riconosciuto.';
  if (asset.fileSizeBytes != null && asset.fileSizeBytes! <= 0) {
    return 'Dimensione del file non valida.';
  }
  final duration = asset.durationSeconds;
  if (asset.kind != MediaKind.image &&
      (duration == null || !duration.isFinite || duration <= 0)) {
    return 'Durata del contenuto non valida.';
  }
  if (asset.kind == MediaKind.image && duration != null &&
      (!duration.isFinite || duration < 0)) {
    return 'Durata immagine non valida.';
  }
  final mime = asset.mimeType?.trim().toLowerCase();
  if (mime != null && mime.isNotEmpty) {
    final expectedPrefix = switch (asset.kind) {
      MediaKind.video => 'video/',
      MediaKind.image => 'image/',
      MediaKind.audio => 'audio/',
      MediaKind.unknown => '',
    };
    if (!mime.startsWith(expectedPrefix)) return 'Tipo MIME incompatibile con il file.';
  }
  return null;
}
