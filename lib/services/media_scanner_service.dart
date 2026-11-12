import 'package:media_scanner/media_scanner.dart';

/// Asks Android's MediaStore to re-index a path so galleries and file apps
/// reflect a rename immediately instead of after a reboot.
class MediaScannerService {
  /// Scans [path]. Pass [alsoParent] to also re-index the containing directory,
  /// which removes stale entries for a folder that was just renamed.
  Future<void> refresh(String path, {String? alsoParent}) async {
    try {
      await MediaScanner.loadMedia(path: path);
      if (alsoParent != null && alsoParent.isNotEmpty) {
        await MediaScanner.loadMedia(path: alsoParent);
      }
    } on Exception {
      // Scanning is best-effort: a failure must never break a successful rename.
    }
  }

  /// Re-indexes every path in [paths] exactly once.
  ///
  /// Used after a batch rename so a single pass covers every affected folder.
  Future<void> refreshAll(Iterable<String> paths) async {
    for (final path in paths.toSet()) {
      if (path.isEmpty) continue;
      await refresh(path);
    }
  }
}
