import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/folder_service.dart';
import '../services/hidden_store.dart';
import '../services/permission_service.dart';
import '../services/rescan_service.dart';
import '../widgets/message_view.dart';
import 'folder_picker_screen.dart';

/// Lists the items this app is currently hiding and drives hide/unhide.
class HomeScreen extends StatefulWidget {
  HomeScreen({
    super.key,
    required this.onOpenSettings,
    HiddenFolderStore? store,
    FolderService? folders,
    RescanService? rescanService,
    PermissionService? permissions,
  }) : store = store ?? HiddenFolderStore(),
       folders = folders ?? FolderService(),
       rescanService = rescanService ?? RescanService(),
       permissions = permissions ?? PermissionService();

  final VoidCallback onOpenSettings;
  final HiddenFolderStore store;
  final FolderService folders;
  final RescanService rescanService;
  final PermissionService permissions;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HiddenFolderStore get _store => widget.store;
  FolderService get _folders => widget.folders;
  RescanService get _rescanService => widget.rescanService;
  PermissionService get _permissions => widget.permissions;

  List<String> _hidden = const [];
  final Set<String> _selectedHidden = <String>{};
  bool _loading = true;
  bool _busy = false;
  StorageAccess _access = StorageAccess.denied;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final access = await _permissions.status();
    final hidden = access == StorageAccess.granted
        ? await _store.pruneMissing()
        : await _store.all();
    if (!mounted) return;
    setState(() {
      _access = access;
      _hidden = hidden;
      _selectedHidden.removeWhere((path) => !hidden.contains(path));
      _loading = false;
    });
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _hideFolder() async {
    if (_access != StorageAccess.granted) {
      _notify('Grant file access first.');
      return;
    }

    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    // The picker skips already-hidden items, but a rescan or an external
    // change may have hidden one in the meantime.
    final targets = selected
        .where((path) => !FolderService.isHidden(path))
        .toList(growable: false);
    if (targets.isEmpty) {
      _notify('Those items are already hidden.');
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await _folders.hideAll(targets);
      for (final change in result.changes) {
        await _store.rebaseDescendants(change.sourcePath, change.targetPath);
      }
      for (final path in result.hidden) {
        await _store.add(path);
      }
      await _load();
      _notify(_summarize(result));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Turns a batch outcome into a single short line, naming the first failure.
  String _summarize(BatchHideResult result) {
    final hidden = result.hidden.length;
    if (!result.hasFailures) {
      return 'Hidden $hidden item${hidden == 1 ? '' : 's'}';
    }

    final first = result.failed.first;
    final reason = '${FolderService.displayName(first.path)}: ${first.message}';
    if (hidden == 0) {
      return result.failed.length == 1
          ? reason
          : 'Could not hide any items. $reason';
    }
    final failed = result.failed.length;
    return 'Hidden $hidden item${hidden == 1 ? '' : 's'}, $failed failed — $reason';
  }

  Future<void> _unhide(String path) async {
    final confirmed = await _confirmUnhide(path);
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final newPath = await _folders.unhide(path);
      await _store.remove(path);
      await _store.rebaseDescendants(path, newPath);
      await _load();
      _notify('Restored ${FolderService.displayName(newPath)}');
    } on FolderOperationException catch (error) {
      _notify(error.message);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unhideSelected() async {
    if (_access != StorageAccess.granted) {
      _notify('Grant file access first.');
      return;
    }
    final selected = _selectedHidden.toList(growable: false);
    if (selected.isEmpty) return;

    final confirmed = await _confirmUnhideSelected(selected.length);
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await _folders.unhideAll(selected);
      for (final change in result.changes) {
        await _store.remove(change.sourcePath);
        await _store.rebaseDescendants(change.sourcePath, change.targetPath);
      }
      if (mounted) setState(_selectedHidden.clear);
      await _load();
      _notify(_summarizeUnhide(result));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmUnhideSelected(int count) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Unhide $count item${count == 1 ? '' : 's'}?'),
      content: const Text(
        'Selected items will become visible again in galleries and file apps.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Unhide'),
        ),
      ],
    ),
  );

  String _summarizeUnhide(BatchUnhideResult result) {
    final restored = result.unhidden.length;
    if (!result.hasFailures) {
      return 'Restored $restored item${restored == 1 ? '' : 's'}';
    }

    final first = result.failed.first;
    final reason = '${FolderService.displayName(first.path)}: ${first.message}';
    if (restored == 0) {
      return result.failed.length == 1
          ? reason
          : 'Could not restore any items. $reason';
    }
    return 'Restored $restored item${restored == 1 ? '' : 's'}, '
        '${result.failed.length} failed — $reason';
  }

  void _toggleHiddenSelection(String path) {
    setState(() {
      if (!_selectedHidden.add(path)) _selectedHidden.remove(path);
    });
  }

  void _selectAllHidden() => setState(() => _selectedHidden.addAll(_hidden));

  void _clearHiddenSelection() => setState(_selectedHidden.clear);

  Future<bool?> _confirmUnhide(String path) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Unhide item?'),
      content: Text(
        '"${FolderService.displayName(path)}" will become visible again in galleries and file apps.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Unhide'),
        ),
      ],
    ),
  );

  Future<void> _rescan() async {
    if (_access != StorageAccess.granted) {
      _notify('Grant file access first.');
      return;
    }

    setState(() => _busy = true);
    try {
      final known = (await _store.all()).toSet();
      final candidates = await _rescanService.scan([
        PermissionService.externalStorageRoot,
      ], known: known);

      if (!mounted) return;
      if (candidates.isEmpty) {
        _notify('No hidden items found.');
        return;
      }

      final selected = await _pickCandidates(candidates);
      if (selected.isEmpty) return;

      final merged = {...known, ...selected.map((candidate) => candidate.path)};
      await _store.replaceAll(merged);
      await _load();
      _notify(
        'Imported ${selected.length} item${selected.length == 1 ? '' : 's'}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<RescanCandidate>> _pickCandidates(
    List<RescanCandidate> candidates,
  ) async {
    final selectedPaths = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: const Text('Found hidden items'),
            contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: candidates.length,
                itemBuilder: (context, index) {
                  final candidate = candidates[index];
                  final checked = selectedPaths.contains(candidate.path);
                  return CheckboxListTile(
                    value: checked,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: Icon(
                      candidate.isDirectory
                          ? Icons.folder_outlined
                          : Icons.insert_drive_file_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      candidate.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      p.dirname(candidate.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selectedPaths.add(candidate.path);
                      } else {
                        selectedPaths.remove(candidate.path);
                      }
                    }),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selectedPaths.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return const [];
    return candidates
        .where((candidate) => selectedPaths.contains(candidate.path))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionMode = _selectedHidden.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: selectionMode
            ? IconButton(
                tooltip: 'Clear selection',
                onPressed: _busy ? null : _clearHiddenSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          selectionMode ? '${_selectedHidden.length} selected' : 'DotHide',
        ),
        actions: selectionMode
            ? [
                IconButton(
                  tooltip: 'Select all',
                  onPressed: _busy || _selectedHidden.length == _hidden.length
                      ? null
                      : _selectAllHidden,
                  icon: const Icon(Icons.select_all),
                ),
              ]
            : [
                if (_hidden.isNotEmpty)
                  IconButton(
                    tooltip: 'Select all hidden items',
                    onPressed: _busy ? null : _selectAllHidden,
                    icon: const Icon(Icons.select_all),
                  ),
                IconButton(
                  tooltip: 'Rescan for hidden items',
                  onPressed: _busy ? null : _rescan,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: widget.onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
      ),
      body: Column(
        children: [
          if (_access != StorageAccess.granted) _AccessBanner(onFix: _load),
          Expanded(child: _buildBody(theme)),
        ],
      ),
      floatingActionButton: _access == StorageAccess.granted
          ? FloatingActionButton.extended(
              onPressed: _busy
                  ? null
                  : (selectionMode ? _unhideSelected : _hideFolder),
              icon: Icon(selectionMode ? Icons.visibility_outlined : Icons.add),
              label: Text(
                selectionMode
                    ? 'Unhide Selected (${_selectedHidden.length})'
                    : 'Hide folders',
              ),
            )
          : null,
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_hidden.isEmpty) {
      return const MessageView(
        icon: Icons.visibility_off_outlined,
        title: 'No hidden items',
        message:
            'Folders and files you hide are listed here. Their name gains a leading dot, '
            'which keeps them out of galleries and file browsers.',
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: _hidden.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final path = _hidden[index];
            return _HiddenEntryTile(
              path: path,
              selected: _selectedHidden.contains(path),
              selectionMode: _selectedHidden.isNotEmpty,
              onToggleSelection: _busy
                  ? null
                  : () => _toggleHiddenSelection(path),
              onUnhide: _busy ? null : () => _unhide(path),
            );
          },
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _HiddenEntryTile extends StatelessWidget {
  const _HiddenEntryTile({
    required this.path,
    required this.selected,
    required this.selectionMode,
    required this.onToggleSelection,
    required this.onUnhide,
  });

  final String path;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggleSelection;
  final VoidCallback? onUnhide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = FolderService.displayName(path);
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    final exists =
        type == FileSystemEntityType.directory ||
        type == FileSystemEntityType.file;
    final isDirectory = type == FileSystemEntityType.directory;

    return Card(
      child: InkWell(
        onTap: selectionMode ? onToggleSelection : onUnhide,
        onLongPress: onToggleSelection,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (selectionMode)
                Checkbox(
                  value: selected,
                  onChanged: onToggleSelection == null
                      ? null
                      : (_) => onToggleSelection!(),
                )
              else
                Icon(
                  !exists
                      ? Icons.help_outline
                      : isDirectory
                      ? Icons.folder_off_outlined
                      : Icons.insert_drive_file_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      exists ? p.dirname(path) : 'Missing on device',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: exists
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
              if (!selectionMode) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: onUnhide, child: const Text('Unhide')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessBanner extends StatelessWidget {
  const _AccessBanner({required this.onFix});

  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'File access is off. Hiding and unhiding are unavailable.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onFix, child: const Text('Fix')),
        ],
      ),
    );
  }
}
