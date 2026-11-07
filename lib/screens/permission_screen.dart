import 'package:flutter/material.dart';

import '../services/permission_service.dart';

/// Explains why broad file access is required and drives the grant flow.
class PermissionScreen extends StatefulWidget {
  const PermissionScreen({
    super.key,
    required this.onGranted,
    this.canSkip = false,
  });

  final VoidCallback onGranted;

  /// When true an "Later" action is offered (used from the settings entry).
  final bool canSkip;

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> with WidgetsBindingObserver {
  final PermissionService _permissions = PermissionService();
  StorageAccess _state = StorageAccess.denied;
  bool _busy = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the all-files settings page: re-check automatically.
    if (state == AppLifecycleState.resumed && _checked) {
      _check(notifyParent: true);
    }
  }

  Future<void> _check({bool notifyParent = false}) async {
    final result = await _permissions.status();
    if (!mounted) return;
    setState(() {
      _state = result;
      _checked = true;
    });
    if (result == StorageAccess.granted && notifyParent) {
      widget.onGranted();
    }
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    final result = await _permissions.request();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _state = result;
    });

    // On Android 11+ the request opens a settings page; the result is only
    // reliable once we come back, which `didChangeAppLifecycleState` handles.
    if (result == StorageAccess.granted) {
      widget.onGranted();
    } else if (mounted) {
      await _check(notifyParent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permanentlyDenied = _state == StorageAccess.permanentlyDenied;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.folder_special_outlined, size: 52, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 24),
              Text(
                'Allow access to files',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'DotHide renames folders on your device. Android requires "All files access" '
                'so it can rename folders anywhere you choose, not just inside the app\'s own '
                'sandbox.\n\n'
                'DotHide never reads, uploads, or changes the contents of your files. It only '
                'adds or removes a leading dot on the folder name.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              if (permanentlyDenied)
                Text(
                  'Access was denied. Open system settings and enable "All files access" '
                  'for DotHide.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (permanentlyDenied) {
                          await _permissions.openSettings();
                          await _check(notifyParent: true);
                        } else {
                          await _request();
                        }
                      },
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(permanentlyDenied ? 'Open settings' : 'Grant access'),
              ),
              if (widget.canSkip) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
