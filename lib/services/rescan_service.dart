import 'dart:io';

import 'package:path/path.dart' as p;

/// A dot-prefixed directory discovered on disk that the app has no record of.
class RescanCandidate {
  RescanCandidate(this.path, this.name);

  final String path;

  /// Folder name without the leading dot.
  final String name;
}

/// Finds already-hidden (dot-prefixed) folders so they can be re-imported after
/// a reinstall, when `SharedPreferences` no longer has them.
class RescanService {
  RescanService({this.maxDepth = 3, this.maxDirectories = 4000});

  /// How deep below each root to search. Keeps the walk predictable on large
  /// cards while still covering the usual `Download/Media/...` layouts.
  final int maxDepth;

  /// Hard cap on visited directories, so a rescan can never hang the app.
  final int maxDirectories;

  /// Dot-folders owned by Android or other tooling. They are not user-hidden
  /// folders and must never be offered for import or accidentally unhidden.
  static const Set<String> _systemDotFolders = {
    '.android',
    '.android_secure',
    '.cache',
    '.config',
    '.db',
    '.downloads',
    '.fonts',
    '.gs_fonts',
    '.highlight',
    '.jamie',
    '.mediadrm',
    '.mmsyscache',
    '.nomedia',
    '.quickedit',
    '.shortcut',
    '.sketch',
    '.temp',
    '.thumbnails',
    '.trashed',
    '.trash',
  };

  /// Walks [roots] and returns dot-prefixed folders not already in [known].
  ///
  /// A folder is treated as a candidate only if the name is a "normal" user
  /// folder that merely has a dot prepended — see [_looksUserHidden].
  Future<List<RescanCandidate>> scan(
    Iterable<String> roots, {
    Set<String> known = const {},
  }) async {
    final found = <String, RescanCandidate>{};
    var visited = 0;

    for (final root in roots) {
      final queue = <(Directory, int)>[(Directory(root), 0)];
      final seen = <String>{};

      while (queue.isNotEmpty && visited < maxDirectories) {
        final (dir, depth) = queue.removeAt(0);
        final normalized = p.normalize(dir.path);
        if (!seen.add(normalized)) continue;
        visited++;

        List<FileSystemEntity> entries;
        try {
          entries = await dir.list(followLinks: false).toList();
        } on FileSystemException {
          continue;
        }

        for (final entry in entries) {
          if (entry is! Directory) continue;
          final name = p.basename(entry.path);

          if (!name.startsWith('.')) {
            if (depth < maxDepth) queue.add((entry, depth + 1));
            continue;
          }

          if (!_looksUserHidden(name)) continue;

          final path = p.normalize(entry.path);
          if (!known.contains(path)) {
            found[path] = RescanCandidate(path, name.substring(1));
          }
          // Hidden folders are not descended into: their contents stay private.
        }
      }
    }

    final result = found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Rejects Android internals and macOS-style junk while accepting real user
  /// folders such as `.MyFolder`, `.2026 Photos`, or `.Trip.v2`.
  static bool _looksUserHidden(String dotName) {
    if (dotName.length < 2) return false;
    if (_systemDotFolders.contains(dotName.toLowerCase())) return false;

    final bare = dotName.substring(1);
    // A second leading dot (e.g. "..") is not something this app creates.
    if (bare.startsWith('.')) return false;
    // Must contain at least one letter or digit to be a real folder name.
    return bare.codeUnits.any((unit) =>
        (unit >= 0x30 && unit <= 0x39) || // 0-9
        (unit >= 0x41 && unit <= 0x5A) || // A-Z
        (unit >= 0x61 && unit <= 0x7A)); // a-z
  }
}
