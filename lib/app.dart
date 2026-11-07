import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/lock_setup_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/settings_screen.dart';
import 'services/biometric_service.dart';
import 'services/lock_store.dart';
import 'services/permission_service.dart';

/// Which screen the app should show right now.
enum AppStage { loading, lockSetup, locked, permission, unlocked }

/// Root shell that wires the mandatory lock, the storage permission, and the
/// main content together, and re-locks the app when it returns to foreground.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.lockStore, this.biometricService, this.permissionService});

  final LockStore? lockStore;
  final BiometricService? biometricService;
  final PermissionService? permissionService;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> with WidgetsBindingObserver {
  /// Grace period before an interrupted app is locked again. Short trips to a
  /// system settings page or a folder picker must not force a re-unlock.
  static const Duration _relockGrace = Duration(seconds: 5);

  late final LockStore _lockStore = widget.lockStore ?? LockStore();
  late final BiometricService _biometrics = widget.biometricService ?? BiometricService();
  late final PermissionService _permissions = widget.permissionService ?? PermissionService();

  AppStage _stage = AppStage.loading;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        _handleResume();
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _bootstrap() async {
    if (await _lockStore.hasLock()) {
      _setStage(AppStage.locked);
      return;
    }
    // The very first launch must set a mandatory method before anything else.
    _setStage(AppStage.lockSetup);
  }

  Future<void> _handleResume() async {
    final since = _backgroundedAt;
    _backgroundedAt = null;

    if (since == null) return;
    if (_stage != AppStage.unlocked && _stage != AppStage.permission) return;
    if (DateTime.now().difference(since) < _relockGrace) return;
    if (!await _lockStore.hasLock()) return;
    _setStage(AppStage.locked);
  }

  void _setStage(AppStage stage) {
    if (!mounted || _stage == stage) return;
    setState(() => _stage = stage);
  }

  Future<void> _onSetupDone() async {
    // Offer the fingerprint shortcut by default when the device has one
    // enrolled. It stays optional and is never the only way in.
    if (await _biometrics.hasFingerprint()) {
      await _lockStore.setBiometricEnabled(true);
    }
    _setStage(AppStage.locked);
  }

  Future<void> _onUnlocked() async {
    _setStage(AppStage.permission);
    // Skip the permission screen entirely when access is already granted.
    if (await _permissions.status() == StorageAccess.granted) {
      _setStage(AppStage.unlocked);
    }
  }

  void _onPermissionGranted() => _setStage(AppStage.unlocked);

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      AppStage.loading => const _Splash(),
      AppStage.lockSetup => LockSetupScreen(store: _lockStore, onDone: _onSetupDone),
      AppStage.locked => LockScreen(
          store: _lockStore,
          biometricService: _biometrics,
          onUnlocked: _onUnlocked,
        ),
      AppStage.permission => PermissionScreen(onGranted: _onPermissionGranted),
      AppStage.unlocked => HomeScreen(
          onOpenSettings: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsScreen(
                store: _lockStore,
                biometricService: _biometrics,
              ),
            ),
          ),
        ),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
