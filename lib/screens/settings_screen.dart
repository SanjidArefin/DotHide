import 'package:flutter/material.dart';

import '../services/biometric_service.dart';
import '../services/lock_store.dart';
import '../widgets/lock_verify_dialog.dart';
import 'lock_setup_screen.dart';

/// App settings: change the mandatory unlock method and toggle the fingerprint
/// shortcut. Fingerprint can only be enabled while a mandatory method exists.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, this.biometricService});

  final LockStore store;
  final BiometricService? biometricService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final BiometricService _biometrics = widget.biometricService ?? BiometricService();

  LockType? _type;
  bool _biometricEnabled = false;
  bool _fingerprintAvailable = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final type = await widget.store.type();
    final enabled = await widget.store.biometricEnabled();
    final available = await _biometrics.hasFingerprint();
    if (!mounted) return;
    setState(() {
      _type = type;
      _biometricEnabled = enabled;
      _fingerprintAvailable = available;
      _loading = false;
    });
  }

  Future<void> _changeLock() async {
    final type = _type;
    if (type != null) {
      final verified = await LockVerifyDialog.show(context, store: widget.store, type: type);
      if (!verified || !mounted) return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LockSetupScreen(
          store: widget.store,
          mode: LockSetupMode.change,
          onDone: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    await _load();
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value && _type == null) return;
    if (value && !_fingerprintAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No fingerprint enrolled on this device.')));
      return;
    }
    await widget.store.setBiometricEnabled(value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const _SectionHeader('Security'),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Unlock method'),
                  subtitle: Text(_type?.label ?? 'Not set'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changeLock,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Fingerprint shortcut'),
                  subtitle: Text(
                    _type == null
                        ? 'Set a PIN, password, or pattern first'
                        : (_fingerprintAvailable
                            ? 'Unlock with your fingerprint — ${_type!.label} stays as fallback'
                            : 'No fingerprint enrolled on this device'),
                  ),
                  value: _biometricEnabled,
                  onChanged: (_type == null || !_fingerprintAvailable) ? null : _toggleBiometric,
                ),
                const Divider(height: 32),
                const _SectionHeader('About'),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('How hiding works'),
                  subtitle: Text(
                    'Folders are hidden by adding a leading dot to the name. No files are moved, '
                    'encrypted, or modified, and nothing is uploaded.',
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.restart_alt),
                  title: Text('After reinstalling'),
                  subtitle: Text(
                    'Hidden folders stay hidden because the dot is part of the name. Use "Rescan" '
                    'on the home screen to bring them back into this list.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.text_fields, color: theme.colorScheme.onSurfaceVariant),
                  title: const Text('Version'),
                  subtitle: const Text('1.0.1'),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
