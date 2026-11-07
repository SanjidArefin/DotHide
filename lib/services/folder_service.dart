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

  Future<String> _toggle(String folderPath, {required bool hide}) async {
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
      await _scanner.refresh(renamed.path, alsoParent: parentPath);
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
