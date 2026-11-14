import 'dart:io';

import 'package:path/path.dart' as p;

import 'media_scanner_service.dart';

/// Thrown when a filesystem item cannot be hidden or unhidden.
class FolderOperationException implements Exception {
  FolderOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A selected item that could not be processed during a batch operation.
class BatchHideFailure {
  BatchHideFailure(this.path, this.message);

  /// The path that was requested, before any rename was attempted.
  final String path;

  /// Why the operation failed, ready to display.
  final String message;
}

/// A successful per-item rename performed by a batch operation.
class FolderPathChange {
  FolderPathChange(this.sourcePath, this.targetPath);

  /// The item's path immediately before this rename.
  final String sourcePath;

  /// The item's path immediately after this rename.
  final String targetPath;
}

/// Outcome of [FolderService.hideAll].
class BatchHideResult {
  BatchHideResult({
    required this.hidden,
    required this.failed,
    this.changes = const [],
  });

  /// Final dot-prefixed paths, after accounting for renamed ancestors.
  final List<String> hidden;

  /// Items that were skipped, with a reason for each.
  final List<BatchHideFailure> failed;

  /// Successful renames in the order they were applied.
  final List<FolderPathChange> changes;

  bool get hasFailures => failed.isNotEmpty;
}

/// Outcome of [FolderService.unhideAll].
class BatchUnhideResult {
  BatchUnhideResult({
    required this.unhidden,
    required this.failed,
    this.changes = const [],
  });

  /// Final visible paths, after accounting for renamed ancestors.
  final List<String> unhidden;

  /// Items that were skipped, with a reason for each.
  final List<BatchHideFailure> failed;

  /// Successful renames in the order they were applied.
  final List<FolderPathChange> changes;

  bool get hasFailures => failed.isNotEmpty;
}

/// Hides a file or folder by toggling a leading `.` on its name.
///
/// The item itself is renamed. Folder contents and file contents are never
/// read, copied, or changed.
class FolderService {
  FolderService({MediaScannerService? scanner})
    : _scanner = scanner ?? MediaScannerService();

  static const String _dot = '.';

  final MediaScannerService _scanner;

  /// Renames `Holiday` to `.Holiday` and notifies the media scanner.
  Future<String> hide(String itemPath) => _toggle(itemPath, hide: true);

  /// Renames `.Holiday` back to `Holiday` and notifies the media scanner.
  Future<String> unhide(String itemPath) => _toggle(itemPath, hide: false);

  /// Hides files and folders in a batch, processing descendants before parents.
  ///
  /// Each item is renamed independently. A failure does not stop the remaining
  /// items. Successful ancestor renames are reflected in returned paths.
  Future<BatchHideResult> hideAll(Iterable<String> itemPaths) async {
    final outcome = await _runBatch(itemPaths, hide: true);
    return BatchHideResult(
      hidden: outcome.paths,
      failed: outcome.failed,
      changes: outcome.changes,
    );
  }

  /// Unhides files and folders in a batch, processing parents before descendants.
  Future<BatchUnhideResult> unhideAll(Iterable<String> itemPaths) async {
    final outcome = await _runBatch(itemPaths, hide: false);
    return BatchUnhideResult(
      unhidden: outcome.paths,
      failed: outcome.failed,
      changes: outcome.changes,
    );
  }

  Future<_BatchOutcome> _runBatch(
    Iterable<String> itemPaths, {
    required bool hide,
  }) async {
    final unique = <String>{};
    final indexed = <_IndexedPath>[];
    for (final itemPath in itemPaths) {
      final path = _normalize(itemPath);
      if (unique.add(path)) indexed.add(_IndexedPath(path, indexed.length));
    }

    indexed.sort((a, b) {
      final depthOrder = _depth(a.path).compareTo(_depth(b.path));
      if (depthOrder != 0) return hide ? -depthOrder : depthOrder;
      return a.index.compareTo(b.index);
    });

    final changes = <FolderPathChange>[];
    final failed = <BatchHideFailure>[];
    final finalPaths = <String>[];

    for (final item in indexed) {
      var sourcePath = item.path;
      for (final change in changes) {
        sourcePath = _rewritePrefix(
          sourcePath,
          change.sourcePath,
          change.targetPath,
        );
      }

      try {
        final targetPath = await _renameWithoutScan(sourcePath, hide: hide);
        final change = FolderPathChange(sourcePath, targetPath);
        for (var i = 0; i < finalPaths.length; i++) {
          finalPaths[i] = _rewritePrefix(finalPaths[i], sourcePath, targetPath);
        }
        finalPaths.add(targetPath);
        changes.add(change);
      } on FolderOperationException catch (error) {
        failed.add(BatchHideFailure(item.path, error.message));
      }
    }

    final scanPaths = <String>{};
    for (final path in finalPaths) {
      scanPaths
        ..add(path)
        ..add(p.dirname(path));
    }
    await _scanner.refreshAll(scanPaths);

    return _BatchOutcome(paths: finalPaths, failed: failed, changes: changes);
  }

  Future<String> _toggle(String itemPath, {required bool hide}) async {
    final renamed = await _renameWithoutScan(itemPath, hide: hide);
    await _scanner.refresh(renamed, alsoParent: p.dirname(renamed));
    return renamed;
  }

  Future<String> _renameWithoutScan(
    String itemPath, {
    required bool hide,
  }) async {
    final normalized = _normalize(itemPath);
    final type = await FileSystemEntity.type(normalized, followLinks: false);
    final source = switch (type) {
      FileSystemEntityType.directory => Directory(normalized),
      FileSystemEntityType.file => File(normalized),
      FileSystemEntityType.notFound => null,
      FileSystemEntityType.link => null,
      _ => null,
    };
    if (source == null) {
      if (type == FileSystemEntityType.link) {
        throw FolderOperationException(
          'Links cannot be hidden. Select a file or folder instead.',
        );
      }
      throw FolderOperationException('Item no longer exists: $normalized');
    }

    final noun = source is Directory ? 'Folder' : 'File';
    final name = p.basename(normalized);
    final isHidden = name.startsWith(_dot);
    final bareName = isHidden ? name.substring(1) : name;

    if (bareName.isEmpty) {
      throw FolderOperationException('Cannot toggle an item named "."');
    }
    if (hide && isHidden) {
      throw FolderOperationException('$noun is already hidden.');
    }
    if (!hide && !isHidden) {
      throw FolderOperationException('$noun is not hidden.');
    }

    final targetName = hide ? '$_dot$bareName' : bareName;
    final targetPath = p.join(p.dirname(normalized), targetName);
    if (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FolderOperationException(
        '"$targetName" already exists in this location.',
      );
    }

    try {
      if (source is Directory) {
        return (await source.rename(targetPath)).path;
      }
      return (await (source as File).rename(targetPath)).path;
    } on FileSystemException catch (error) {
      throw FolderOperationException(_describe(error));
    }
  }

  /// True when the filesystem item's name starts with a dot.
  static bool isHidden(String itemPath) =>
      p.basename(_normalize(itemPath)).startsWith(_dot);

  /// The visible name, with one leading hiding dot removed.
  static String displayName(String itemPath) {
    final name = p.basename(_normalize(itemPath));
    return name.startsWith(_dot) ? name.substring(1) : name;
  }

  static String _normalize(String path) {
    var value = path.trim();
    while (value.length > 1 && (value.endsWith('/') || value.endsWith('\\'))) {
      value = value.substring(0, value.length - 1);
    }
    return p.normalize(value);
  }

  static int _depth(String path) => p.split(path).length;

  static String _rewritePrefix(String path, String source, String target) {
    final normalizedPath = _normalize(path);
    final normalizedSource = _normalize(source);
    final normalizedTarget = _normalize(target);
    if (normalizedPath == normalizedSource) return normalizedTarget;
    if (!p.isWithin(normalizedSource, normalizedPath)) return normalizedPath;
    return p.join(
      normalizedTarget,
      p.relative(normalizedPath, from: normalizedSource),
    );
  }

  static String _describe(FileSystemException error) {
    final code = error.osError?.errorCode;
    return switch (code) {
      1 || 13 => 'Permission denied. Grant all-files access and try again.',
      17 => 'A file or folder with that name already exists.',
      30 => 'The item is in use by another app. Close it and retry.',
      _ => error.osError?.message ?? 'Could not rename the item.',
    };
  }
}

class _IndexedPath {
  const _IndexedPath(this.path, this.index);

  final String path;
  final int index;
}

class _BatchOutcome {
  const _BatchOutcome({
    required this.paths,
    required this.failed,
    required this.changes,
  });

  final List<String> paths;
  final List<BatchHideFailure> failed;
  final List<FolderPathChange> changes;
}
