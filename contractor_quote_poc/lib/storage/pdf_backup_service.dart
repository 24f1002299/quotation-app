import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'pdf_backup_settings.dart';

/// Day 18 — Optional cloud backup for quotation PDFs.
///
/// Contract: never uploads unless [PdfBackupSettings.isOptedIn] is true.
/// App-scoped local storage is always the source of truth; Storage is only
/// a recovery copy under `user-files/<userId>/quote-pdfs/<quoteId>.pdf`.
class PdfBackupService {
  /// Uploads the local PDF at [pdfPath] when backup is opted in.
  /// Returns the remote storage path on success, null when skipped/offline.
  static Future<String?> backupPdfIfOptedIn({
    required String quoteId,
    required String pdfPath,
  }) async {
    if (!await PdfBackupSettings.isOptedIn()) return null;

    final file = File(pdfPath);
    if (!await file.exists()) return null;

    String userId = 'local_contractor';
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) userId = user.id;
    } catch (_) {
      // Supabase uninitialized in tests — fall through to local id.
    }

    final sanitizedId = quoteId.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final remotePath = '$userId/quote-pdfs/$sanitizedId.pdf';

    try {
      final bytes = await file.readAsBytes();
      await Supabase.instance.client.storage.from('user-files').uploadBinary(
            remotePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );
      return remotePath;
    } catch (_) {
      return null;
    }
  }
}
