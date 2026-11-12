import 'dart:io';

import 'package:path/path.dart' as p;

import 'media_scanner_service.dart';

/// Thrown when a folder cannot be hidden or unhidden.
class FolderOperationException implements Exception {
  FolderOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A folder that could not be hidden during a batch operation.
class BatchHideFailure {
  BatchHideFailure(this.path, this.message);

  /// The path that was requested, before any rename was attempted.
  final String path;

  /// Why the folder could not be hidden, ready to display.
  final String message;
}

/// Outcome of [FolderService.hideAll].
class BatchHideResult {
  BatchHideResult({required this.hidden, required this.failed});

  /// New dot-prefixed paths, in the order the folders were processed.
  final List<String> hidden;

  /// Folders that were skipped, with a reason for each.
  final List<BatchHideFailure> failed;

  bool get hasFailures => failed.isNotEmpty;
}

/// Hides/unhides a folder purely by toggling a leading `.` on its name.
///
/// Only `Directory.rename` is used — files inside are never moved, renamed,
/// read, or processed in any way.
class FolderService {
  FolderService({MediaScannerService? scanner}) : _scanner = scanner ?? MediaScannerService();

  static const String _dot = '.';

  final MediaScannerService _scanner;

  /// Renames `MyFolder` to `.MyFolder` and notifies the media scanner.
  Future<String> hide(String folderPath) =>
      _toggle(folderPath, hide: true);

  /// Renames `.MyFolder` back to `MyFolder` and notifies the media scanner.
  Future<String> unhide(String folderPath) =>
      _toggle(folderPath, hide: false);

  /// Hides several folders in one pass.
  ///
  /// Each rename still happens individually — folders are never moved together —
  /// but the media scanner is refreshed once for the whole batch. A folder that
  /// cannot be hidden (missing, already hidden, or a name collision) is reported
  /// in [BatchHideResult.failed] and does not stop the remaining folders.
  Future<BatchHideResult> hideAll(Iterable<String> folderPaths) async {
    final hidden = <String>[];
    final failed = <BatchHideFailure>[];
    final scanned = <String>{};

    for (final path in folderPaths) {
      try {
        final renamed = await _hideWithoutScan(path);
        hidden.add(renamed);
        scanned.add(renamed);
        // The parent is re-indexed too so the old name leaves the MediaStore.
        scanned.add(Directory(renamed).parent.path);
      } on FolderOperationException catch (error) {
        failed.add(BatchHideFailure(path, error.message));
      }
    }

    await _scanner.refreshAll(scanned);
    return BatchHideResult(hidden: hidden, failed: failed);
  }

  Future<String> _toggle(String folderPath, {required bool hide}) async {
    final renamed = await _hideWithoutScan(folderPath, hide: hide);
    await _scanner.refresh(renamed, alsoParent: Directory(renamed).parent.path);
    return renamed;
  }

  Future<String> _hideWithoutScan(String folderPath, {bool hide = true}) async {
    final normalized = _normalize(folderPath);
    final source = Directory(normalized);

    if (!await source.exists()) {
      throw FolderOperationException('Folder no longer exists: $normalized');
    }

    final parentPath = source.parent.path;
    final name = p.basename(normalized);
    final isHidden = name.startsWith(_dot);
    final bareName = isHidden ? name.substring(1) : name;

    if (bareName.isEmpty) {
      throw FolderOperationException('Cannot toggle a folder named "."');
    }
    if (hide && isHidden) {
      throw FolderOperationException('Folder is already hidden.');
    }
    if (!hide && !isHidden) {
      throw FolderOperationException('Folder is not hidden.');
    }

    final targetName = hide ? '$_dot$bareName' : bareName;
    final targetPath = p.join(parentPath, targetName);

    if (await Directory(targetPath).exists() || await File(targetPath).exists()) {
      throw FolderOperationException('"$targetName" already exists in this location.');
    }

    try {
      final renamed = await source.rename(targetPath);
      return renamed.path;
    } on FileSystemException catch (error) {
      throw FolderOperationException(_describe(error));
    }
  }

  /// True when the folder name starts with a dot.
  static bool isHidden(String folderPath) =>
      p.basename(_normalize(folderPath)).startsWith(_dot);

  /// The folder name as shown in the UI, i.e. without the hiding dot.
  static String displayName(String folderPath) {
    final name = p.basename(_normalize(folderPath));
    return name.startsWith(_dot) ? name.substring(1) : name;
  }

  static String _normalize(String path) {
    var value = path.trim();
    while (value.length > 1 && (value.endsWith('/') || value.endsWith('\\'))) {
      value = value.substring(0, value.length - 1);
    }
    return p.normalize(value);
  }

  static String _describe(FileSystemException error) {
    final code = error.osError?.errorCode;
    return switch (code) {
      1 || 13 => 'Permission denied. Grant all-files access and try again.',
      17 => 'A folder with that name already exists.',
      30 => 'The folder is in use by another app. Close it and retry.',
      _ => error.osError?.message ?? 'Could not rename the folder.',
    };
  }
}
