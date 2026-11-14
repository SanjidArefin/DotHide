import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/permission_service.dart';

typedef FolderEntryLoader = Future<List<FileSystemEntity>> Function(
  String path,
);

/// Built-in directory browser used to choose files and folders to hide.
///
/// It relies on the all-files access granted earlier, so it can start at the
/// shared external storage root and walk anywhere the user has access.
/// Long-press or check items to select them. Folder navigation remains available
/// through each folder's trailing arrow. Pops with the checked paths.
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({
    super.key,
    this.rootPath = PermissionService.externalStorageRoot,
    this.initialPath,
    this.entryLoader,
  });

  final String rootPath;
  final String? initialPath;
  final FolderEntryLoader? entryLoader;

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  late String _current;
  List<FileSystemEntity> _entries = const [];
  bool _loading = true;
  String? _error;

  /// Checked paths keyed by normalized path, so the current folder's row can be
  /// rendered as checked without a second data structure.
  final Map<String, String> _checked = {};

  @override
  void initState() {
    super.initState();
    _current = widget.initialPath ?? widget.rootPath;
    _load();
  }

  bool get _atRoot => p.normalize(_current) == p.normalize(widget.rootPath);

  bool get _currentChecked => _checked.containsKey(p.normalize(_current));

  bool get _allCurrentChecked =>
      _entries.isNotEmpty &&
      _entries.every((entry) => _checked.containsKey(p.normalize(entry.path)));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final directory = Directory(_current);
    try {
      final List<FileSystemEntity> entries;
      final loader = widget.entryLoader;
      if (loader != null) {
        entries = (await loader(directory.path)).toList();
      } else {
        if (!await directory.exists()) {
          throw const FileSystemException('Folder is not accessible');
        }
        entries = await directory
            .list(followLinks: false)
            .where((entity) => entity is Directory || entity is File)
            .cast<FileSystemEntity>()
            .where((entry) => !p.basename(entry.path).startsWith('.'))
            .toList();
      }

      entries.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.osError?.message ?? 'Cannot read this folder.';
      });
    }
  }

  void _open(String path) {
    setState(() => _current = path);
    _load();
  }

  void _goUp() {
    final parent = Directory(_current).parent.path;
    if (_atRoot) {
      return;
    }
    if (p.normalize(parent).length < p.normalize(widget.rootPath).length) {
      return;
    }
    setState(() => _current = parent);
    _load();
  }

  void _toggle(String path) {
    final normalized = p.normalize(path);
    setState(() {
      if (_checked.remove(normalized) == null) {
        _checked[normalized] = normalized;
      }
    });
  }

  void _toggleAllCurrent() {
    setState(() {
      if (_allCurrentChecked) {
        for (final entry in _entries) {
          _checked.remove(p.normalize(entry.path));
        }
      } else {
        for (final entry in _entries) {
          final path = p.normalize(entry.path);
          _checked[path] = path;
        }
      }
    });
  }

  void _finish() =>
      Navigator.of(context).pop(_checked.values.toList(growable: false));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _checked.length;
    final allCurrentChecked = _allCurrentChecked;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          count == 0 ? 'Choose files and folders' : '$count selected',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_upward),
          tooltip: 'Up one level',
          onPressed: _atRoot ? null : _goUp,
        ),
        actions: [
          if (_entries.isNotEmpty)
            TextButton(
              onPressed: _toggleAllCurrent,
              child: Text(allCurrentChecked ? 'Deselect all' : 'Select all'),
            ),
          if (count > 0)
            TextButton(
              onPressed: () => setState(_checked.clear),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Text(
              _current,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _atRoot ? null : () => _toggle(_current),
              icon: Icon(
                _currentChecked
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
              label: Text(
                _atRoot
                    ? 'Cannot pick the storage root'
                    : (_currentChecked
                          ? 'Uncheck this folder'
                          : 'Check this folder'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: count == 0 ? null : _finish,
              icon: const Icon(Icons.visibility_off_outlined),
              label: Text(
                count == 0
                    ? 'Select items to hide'
                    : 'Hide Selected ($count ${count == 1 ? 'item' : 'items'})',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Cannot open this folder',
        message: _error!,
      );
    }
    if (_entries.isEmpty) {
      return const _Message(
        icon: Icons.folder_off_outlined,
        title: 'No files or subfolders',
        message: 'This folder has no visible items to show. Check this folder instead to hide it.',
      );
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final path = p.normalize(entry.path);
        final name = p.basename(path);
        final checked = _checked.containsKey(path);
        final isDirectory = entry is Directory;

        return ListTile(
          leading: Checkbox(
            value: checked,
            onChanged: (_) => _toggle(path),
            semanticLabel: 'Select $name',
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(isDirectory ? 'Folder' : 'File'),
          trailing: isDirectory
              ? IconButton(
                  tooltip: 'Open folder',
                  icon: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.outline,
                  ),
                  onPressed: () => _open(path),
                )
              : null,
          onTap: () {
            if (_checked.isNotEmpty || !isDirectory) {
              _toggle(path);
            } else {
              _open(path);
            }
          },
          onLongPress: () => _toggle(path),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
