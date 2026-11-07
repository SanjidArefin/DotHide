import 'package:flutter/material.dart';

import '../services/lock_store.dart';
import 'pattern_lock.dart';
import 'pin_pad.dart';

/// Modal that asks the user to prove they know the current unlock secret.
///
/// Used before changing the lock method from settings. Returns `true` when the
/// entered secret matches the stored one.
class LockVerifyDialog extends StatefulWidget {
  const LockVerifyDialog({
    super.key,
    required this.store,
    required this.type,
    this.title,
  });

  final LockStore store;
  final LockType type;
  final String? title;

  /// Shows the dialog and resolves to `true` only on a successful match.
  static Future<bool> show(BuildContext context, {required LockStore store, required LockType type}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LockVerifyDialog(store: store, type: type),
    );
    return result ?? false;
  }

  @override
  State<LockVerifyDialog> createState() => _LockVerifyDialogState();
}

class _LockVerifyDialogState extends State<LockVerifyDialog> {
  final TextEditingController _passwordController = TextEditingController();

  String _pin = '';
  String? _error;
  int _patternErrorFlash = 0;
  int _pinLength = 4;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPinLength();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadPinLength() async {
    if (widget.type != LockType.pin) return;
    final length = await widget.store.pinLength();
    if (!mounted || length == null) return;
    setState(() => _pinLength = length);
  }

  Future<void> _verify(String secret) async {
    if (_busy || secret.isEmpty) return;
    setState(() => _busy = true);
    final ok = await widget.store.verify(secret);
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = 'Incorrect ${widget.type.label.toLowerCase()}.';
      _pin = '';
      _passwordController.clear();
      _patternErrorFlash++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? 'Confirm your ${widget.type.label.toLowerCase()}'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(width: 300, child: _buildInput()),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        if (widget.type == LockType.password)
          FilledButton(onPressed: () => _verify(_passwordController.text), child: const Text('Confirm')),
      ],
    );
  }

  Widget _buildInput() {
    switch (widget.type) {
      case LockType.pin:
        return PinPad(
          value: _pin,
          length: _pinLength,
          errorText: _error,
          onChanged: (value) => setState(() {
            _pin = value;
            _error = null;
          }),
          onCompleted: () => _verify(_pin),
        );

      case LockType.pattern:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 260,
              width: 260,
              child: PatternLock(errorFlash: _patternErrorFlash, onCompleted: (pattern) {
                _verify(pattern.join('-'));
              }),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        );

      case LockType.password:
        return TextField(
          controller: _passwordController,
          obscureText: true,
          autofocus: true,
          onSubmitted: _verify,
          decoration: InputDecoration(labelText: 'Password', errorText: _error),
        );
    }
  }
}
