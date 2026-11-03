import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'file_sharing_service.dart';

/// Concrete system-share implementation. The caller must pass an existing export.
class SharePlusBackend implements FileSharingBackend {
  const SharePlusBackend();

  @override
  Future<void> shareFile({String? title, String? text, required String filePath}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File da condividere non trovato', filePath);
    }
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: title ?? 'Creazione',
      text: text,
    );
  }
}
