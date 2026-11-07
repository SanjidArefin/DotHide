import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the tiny list of hidden folder paths.
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

  /// Drops entries that no longer exist on disk, so the list always reflects
  /// what is actually hidden. Returns the surviving paths.
  Future<List<String>> pruneMissing() async {
    final current = await all();
    final alive = <String>[];
    for (final path in current) {
      if (await Directory(path).exists()) alive.add(path);
    }
    if (alive.length != current.length) {
      await replaceAll(alive);
    }
    return alive;
  }
}
