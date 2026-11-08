import 'dart:io';

/// Contract for native share sheets. Implement with a platform share plugin
/// (for example share_plus) and provide the file path after a successful export.
abstract interface class FileSharingBackend {
  Future<void> shareFile({
    required String filePath,
    String? title,
    String? text,
  });
}

class FileSharingService {
  const FileSharingService(this.backend);

  final FileSharingBackend backend;

  Future<void> shareExport({
    required String filePath,
    String? title,
    String? text,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File esportato non trovato', filePath);
    }
    await backend.shareFile(
      filePath: filePath,
      title: title ?? 'Video',
      text: text,
    );
  }
}
