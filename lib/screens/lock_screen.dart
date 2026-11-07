import 'package:flutter/material.dart';

import '../services/biometric_service.dart';
import '../services/lock_store.dart';
import '../widgets/pattern_lock.dart';
import '../widgets/pin_pad.dart';

/// Full-screen unlock gate.
///
/// The mandatory method (PIN / Password / Pattern) is always offered.
/// Fingerprint, when enabled and available, is an accelerator: any failure,
/// cancellation, or hardware problem silently leaves the mandatory method
/// on screen.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.store,
    required this.onUnlocked,
    this.biometricService,
    this.title = 'Enter your unlock method',
  });

  final LockStore store;
  final VoidCallback onUnlocked;
  final BiometricService? biometricService;
  final String title;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const int _maxAttempts = 5;

  late final BiometricService _biometrics = widget.biometricService ?? BiometricService();

  LockType? _type;
  int _pinLength = 4;
  bool _biometricOffered = false;
  bool _biometricBusy = false;

  String _pin = '';
  final TextEditingController _passwordController = TextEditingController();
  String? _error;
  int _attempts = 0;
  int _patternErrorFlash = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final type = await widget.store.type();
    if (!mounted) return;
    final pinLength = type == LockType.pin ? (await widget.store.pinLength() ?? 4) : 4;
    final biometricEnabled = await widget.store.biometricEnabled();
    final biometricReady = biometricEnabled && await _biometrics.isAvailable();

    if (!mounted) return;
    setState(() {
      _type = type;
      _pinLength = pinLength;
      _biometricOffered = biometricReady;
      _loading = false;
    });

    if (biometricReady) {
      // Give the gate a frame to render before the system prompt appears.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric(auto: true));
    }
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _attempts++;
      _pin = '';
      _passwordController.clear();
      _patternErrorFlash++;
    });
  }

  Future<void> _submitPin(String value) async {
    if (await widget.store.verify(value)) {
      widget.onUnlocked();
      return;
    }
    _fail('Incorrect PIN.');
  }

  Future<void> _submitPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;
    if (await widget.store.verify(password)) {
      widget.onUnlocked();
      return;
    }
    _fail('Incorrect password.');
  }

  Future<void> _submitPattern(List<int> pattern) async {
    if (await widget.store.verify(pattern.join('-'))) {
      widget.onUnlocked();
      return;
    }
    _fail('Incorrect pattern.');
  }

  Future<void> _tryBiometric({bool auto = false}) async {
    if (_biometricBusy) return;
    setState(() => _biometricBusy = true);
    final ok = await _biometrics.authenticate(reason: 'Unlock DotHide');
    if (!mounted) return;
    setState(() => _biometricBusy = false);

    if (ok) {
      widget.onUnlocked();
      return;
    }
    // Fingerprint is only a shortcut — the mandatory method stays available.
    if (!auto) {
      setState(() => _error = 'Fingerprint failed. Use your ${_type?.label ?? 'unlock method'}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_type == null) {
      // Defensive: no mandatory method configured means nothing to gate on.
      widget.onUnlocked();
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Icon(Icons.lock_outline, size: 34),
              const SizedBox(height: 16),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                _subtitle(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (_biometricOffered) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: _biometricBusy ? null : () => _tryBiometric(),
                    icon: const Icon(Icons.fingerprint, size: 20),
                    label: const Text('Use fingerprint'),
                  ),
                ),
              ],
              Expanded(child: Center(child: _buildInput(theme))),
              if (_type == LockType.password) _buildPasswordAction(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    if (_attempts >= _maxAttempts) {
      return 'Too many failed attempts. Take your time.';
    }
    return switch (_type!) {
      LockType.pin => 'Enter your PIN to continue',
      LockType.password => 'Enter your password to continue',
      LockType.pattern => 'Draw your pattern to continue',
    };
  }

  Widget _buildInput(ThemeData theme) {
    switch (_type!) {
      case LockType.pin:
        return PinPad(
          value: _pin,
          length: _pinLength,
          errorText: _error,
          onChanged: (value) => setState(() {
            _pin = value;
            _error = null;
          }),
          onCompleted: () => _submitPin(_pin),
        );

      case LockType.pattern:
        return SizedBox(
          height: 300,
          width: 300,
          child: PatternLock(
            minLength: 4,
            errorFlash: _patternErrorFlash,
            onCompleted: _submitPattern,
          ),
        );

      case LockType.password:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _submitPassword(),
              decoration: InputDecoration(labelText: 'Password', errorText: _error),
            ),
          ],
        );
    }
  }

  Widget _buildPasswordAction() => FilledButton(
        onPressed: _submitPassword,
        child: const Text('Unlock'),
      );
}
