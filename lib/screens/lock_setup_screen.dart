import 'package:flutter/material.dart';

import '../services/lock_store.dart';
import '../widgets/pattern_lock.dart';
import '../widgets/pin_pad.dart';

/// Instructs [LockSetupScreen] whether it is configuring the app for the first
/// time or replacing an existing method from settings.
enum LockSetupMode { onboarding, change }

/// Mandatory lock setup. The user must configure exactly one of
/// PIN / Password / Pattern before the app becomes usable.
class LockSetupScreen extends StatefulWidget {
  const LockSetupScreen({
    super.key,
    required this.store,
    this.mode = LockSetupMode.onboarding,
    this.onDone,
  });

  final LockStore store;
  final LockSetupMode mode;

  /// Called after a successful save. `onboarding` pops with `true` by default.
  final VoidCallback? onDone;

  @override
  State<LockSetupScreen> createState() => _LockSetupScreenState();
}

class _LockSetupScreenState extends State<LockSetupScreen> {
  static const int _pinMinLength = 4;
  static const int _pinMaxLength = 6;
  static const int _passwordMinLength = 6;

  LockType? _type;
  int _pinLength = _pinMinLength;

  // First entry + confirmation entry.
  String _first = '';
  String _confirm = '';
  bool _confirming = false;
  String? _stageError;
  int _patternErrorFlash = 0;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController = TextEditingController();

  bool get _isPin => _type == LockType.pin;
  bool get _isPassword => _type == LockType.password;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  void _selectType(LockType type) {
    setState(() {
      _type = type;
      _reset();
    });
  }

  void _reset() {
    _first = '';
    _confirm = '';
    _confirming = false;
    _stageError = null;
    _passwordController.clear();
    _passwordConfirmController.clear();
  }

  void _backToTypeChoice() {
    setState(() {
      _type = null;
      _reset();
    });
  }

  void _onPinCompleted() {
    // Auto-advance to confirmation once a full-length PIN is entered.
    setState(() {
      _confirming = true;
      _confirm = '';
      _stageError = null;
    });
  }

  void _onPatternCompleted(List<int> pattern) {
    final encoded = pattern.join('-');
    setState(() {
      if (!_confirming) {
        _first = encoded;
        _confirming = true;
        _confirm = '';
        _stageError = null;
      } else {
        _confirm = encoded;
      }
    });
    if (_confirming) {
      _submitPattern();
    }
  }

  Future<void> _submitPattern() async {
    if (_confirm != _first) {
      setState(() {
        _stageError = 'Patterns do not match. Try again.';
        _patternErrorFlash++;
        _first = '';
        _confirm = '';
        _confirming = false;
      });
      return;
    }
    await _persist(LockType.pattern, _first);
  }

  Future<void> _submitPassword() async {
    final password = _passwordController.text;
    if (password.length < _passwordMinLength) {
      setState(() => _stageError = 'Use at least $_passwordMinLength characters.');
      return;
    }
    if (password != _passwordConfirmController.text) {
      setState(() => _stageError = 'Passwords do not match.');
      return;
    }
    await _persist(LockType.password, password);
  }

  Future<void> _submitConfirmStage() async {
    if (_isPin) {
      if (_confirm.length < _pinMinLength) {
        setState(() => _stageError = 'PIN must be at least $_pinMinLength digits.');
        return;
      }
      if (_confirm != _first) {
        setState(() {
          _stageError = 'PINs do not match. Start over.';
          _first = '';
          _confirm = '';
          _confirming = false;
        });
        return;
      }
      await _persist(LockType.pin, _first);
    }
  }

  Future<void> _persist(LockType type, String secret) async {
    await widget.store.setLock(type, secret, pinLength: type == LockType.pin ? secret.length : null);
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == LockSetupMode.onboarding ? 'Set up app lock' : 'Change app lock'),
        leading: widget.mode == LockSetupMode.change
            ? const BackButton()
            : (_type != null ? IconButton(onPressed: _backToTypeChoice, icon: const Icon(Icons.arrow_back)) : null),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _type == null ? _buildTypeChooser(theme) : _buildCapture(theme),
        ),
      ),
    );
  }

  Widget _buildTypeChooser(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.only(top: 24, bottom: 32),
      children: [
        Text(
          'Choose your unlock method',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'One of PIN, Password, or Pattern is required. Fingerprint can be added later '
          'as a shortcut, but this method always remains available as the fallback.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        _MethodCard(
          icon: Icons.pin_outlined,
          title: 'PIN',
          subtitle: '$_pinMinLength–$_pinMaxLength digits, entered on a keypad',
          onTap: () => _selectType(LockType.pin),
        ),
        const SizedBox(height: 12),
        _MethodCard(
          icon: Icons.password_outlined,
          title: 'Password',
          subtitle: 'At least $_passwordMinLength characters',
          onTap: () => _selectType(LockType.password),
        ),
        const SizedBox(height: 12),
        _MethodCard(
          icon: Icons.grid_on_outlined,
          title: 'Pattern',
          subtitle: 'Connect at least 4 dots on a 3x3 grid',
          onTap: () => _selectType(LockType.pattern),
        ),
      ],
    );
  }

  Widget _buildCapture(ThemeData theme) {
    final scheme = theme.colorScheme;
    final instruction = _confirming && !_isPassword ? 'Confirm your ${_type!.label.toLowerCase()}' : _headingForType();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          instruction,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (_stageError != null)
          Text(_stageError!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
        Expanded(child: Center(child: _buildInput(theme))),
        if (_isPassword) _buildPasswordActions(theme),
        if (_isPin && _confirming) _buildPinConfirmActions(theme),
        const SizedBox(height: 16),
      ],
    );
  }

  String _headingForType() => switch (_type!) {
        LockType.pin => 'Create your PIN',
        LockType.password => 'Create your password',
        LockType.pattern => 'Draw your pattern',
      };

  Widget _buildInput(ThemeData theme) {
    switch (_type!) {
      case LockType.pin:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PinPad(
              value: _confirming ? _confirm : _first,
              length: _pinLength,
              errorText: _stageError,
              onChanged: (value) => setState(() {
                if (_confirming) {
                  _confirm = value;
                } else {
                  _first = value;
                }
                _stageError = null;
              }),
              onCompleted: () {
                if (_confirming) {
                  _submitConfirmStage();
                } else {
                  _onPinCompleted();
                }
              },
            ),
            const SizedBox(height: 12),
            if (!_confirming)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Length', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _pinLength,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _pinLength = value;
                        _first = '';
                        _stageError = null;
                      });
                    },
                    items: [
                      for (var i = _pinMinLength; i <= _pinMaxLength; i++)
                        DropdownMenuItem(value: i, child: Text('$i digits')),
                    ],
                  ),
                ],
              ),
          ],
        );

      case LockType.pattern:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 280,
              width: 280,
              child: PatternLock(
                errorFlash: _patternErrorFlash,
                onCompleted: _onPatternCompleted,
                onChanged: (pattern) {
                  if (pattern.isEmpty && _confirm.isNotEmpty) {
                    setState(() => _confirm = '');
                  }
                },
              ),
            ),
          ],
        );

      case LockType.password:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordConfirmController,
              obscureText: true,
              onSubmitted: (_) => _submitPassword(),
              decoration: const InputDecoration(labelText: 'Confirm password'),
            ),
          ],
        );
    }
  }

  Widget _buildPasswordActions(ThemeData theme) => FilledButton(
        onPressed: _submitPassword,
        child: const Text('Save'),
      );

  Widget _buildPinConfirmActions(ThemeData theme) => TextButton(
        onPressed: () => setState(() {
          _first = '';
          _confirm = '';
          _confirming = false;
          _stageError = null;
        }),
        child: const Text('Start over'),
      );
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
