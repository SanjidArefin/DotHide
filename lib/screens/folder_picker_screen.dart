import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/permission_service.dart';

/// Built-in directory browser used to choose a folder to hide.
///
/// It relies on the all-files access granted earlier, so it can start at the
/// shared external storage root and walk anywhere the user has access.
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({
    super.key,
    this.rootPath = PermissionService.externalStorageRoot,
    this.initialPath,
  });

  final String rootPath;
  final String? initialPath;

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  late String _current;
  List<Directory> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = widget.initialPath ?? widget.rootPath;
    _load();
  }

  bool get _atRoot => p.normalize(_current) == p.normalize(widget.rootPath);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final directory = Directory(_current);
    try {
      if (!await directory.exists()) {
        throw const FileSystemException('Folder is not accessible');
      }
      final entries = await directory
          .list(followLinks: false)
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .where((dir) => !p.basename(dir.path).startsWith('.'))
          .toList();

      entries.sort(
        (a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()),
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

  void _open(Directory directory) {
    setState(() => _current = directory.path);
    _load();
  }

  void _goUp() {
    final parent = Directory(_current).parent.path;
    if (_atRoot) return;
    if (p.normalize(parent).length < p.normalize(widget.rootPath).length) return;
    setState(() => _current = parent);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSelect = !_atRoot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose folder'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_upward),
          tooltip: 'Up one level',
          onPressed: _atRoot ? null : _goUp,
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Text(
              _current,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: canSelect ? () => Navigator.of(context).pop(_current) : null,
          child: Text(canSelect ? 'Hide this folder' : 'Open a folder to select it'),
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
        title: 'No subfolders',
        message: 'This folder has no subfolders to show.',
      );
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: theme.colorScheme.outlineVariant),
      itemBuilder: (context, index) {
        final directory = _entries[index];
        return ListTile(
          leading: Icon(Icons.folder_outlined, color: theme.colorScheme.onSurfaceVariant),
          title: Text(p.basename(directory.path), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          onTap: () => _open(directory),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.message});

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
            Text(title, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
