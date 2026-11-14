import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the paths of items hidden by the app.
///
/// This is the only record the app keeps — there is deliberately no per-file
/// mapping or index.
class HiddenFolderStore {
  static const String _key = 'hidden.folders';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<String>> all() async {
    final prefs = await _prefs;
    return prefs.getStringList(_key) ?? const <String>[];
  }

  Future<void> add(String path) async {
    final prefs = await _prefs;
    final current = prefs.getStringList(_key) ?? <String>[];
    if (!current.contains(path)) {
      current.add(path);
      await prefs.setStringList(_key, current);
    }
  }

  Future<void> remove(String path) async {
    final prefs = await _prefs;
    final current = prefs.getStringList(_key) ?? <String>[];
    if (current.remove(path)) {
      await prefs.setStringList(_key, current);
    }
  }

  Future<void> replaceAll(Iterable<String> paths) async {
    final prefs = await _prefs;
    await prefs.setStringList(_key, paths.toSet().toList(growable: false));
  }

  /// Rewrites tracked descendants after a parent directory has been renamed.
  /// The path itself is left alone; callers remove or add that item separately.
  Future<void> rebaseDescendants(
    String oldParentPath,
    String newParentPath,
  ) async {
    final oldParent = p.normalize(oldParentPath);
    final newParent = p.normalize(newParentPath);
    final current = await all();
    var changed = false;
    final updated = <String>[];

    for (final path in current) {
      final normalized = p.normalize(path);
      if (normalized != oldParent && p.isWithin(oldParent, normalized)) {
        updated.add(p.join(newParent, p.relative(normalized, from: oldParent)));
        changed = true;
      } else {
        updated.add(normalized);
      }
    }

    if (changed) await replaceAll(updated);
  }

  /// Drops entries that no longer exist on disk, so the list always reflects
  /// what is actually hidden. Returns the surviving paths.
  Future<List<String>> pruneMissing() async {
    final current = await all();
    final alive = <String>[];
    for (final path in current) {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.directory ||
          type == FileSystemEntityType.file) {
        alive.add(path);
      }
    }
    if (alive.length != current.length) {
      await replaceAll(alive);
    }
    return alive;
  }
}
