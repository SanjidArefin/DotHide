import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double _keySize = 64;

/// Numeric keypad + dot indicator used for both PIN setup and PIN unlock.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.value,
    required this.length,
    required this.onChanged,
    this.errorText,
    this.onCompleted,
  });

  final String value;
  final int length;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final VoidCallback? onCompleted;

  static const List<List<String>> _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  void _append(String digit) {
    if (value.length >= length) return;
    final next = value + digit;
    onChanged(next);
    if (next.length == length) onCompleted?.call();
  }

  void _backspace() {
    if (value.isEmpty) return;
    onChanged(value.substring(0, value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(length, (index) {
            final filled = index < value.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.symmetric(horizontal: 7),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? scheme.onSurface : Colors.transparent,
                border: Border.all(
                  color: errorText != null
                      ? scheme.error
                      : (filled ? scheme.onSurface : scheme.outlineVariant),
                  width: 1.4,
                ),
              ),
            );
          }),
        ),
        SizedBox(
          height: 36,
          child: errorText == null
              ? null
              : Center(
                  child: Text(
                    errorText!,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
        ),
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final digit in row)
                  _KeypadButton(
                    onTap: () => _append(digit),
                    semanticsLabel: digit,
                    label: Text(
                      digit,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: _keySize, height: _keySize),
              _KeypadButton(
                onTap: () => _append('0'),
                semanticsLabel: '0',
                label: Text(
                  '0',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              _KeypadButton(
                onTap: _backspace,
                semanticsLabel: 'Delete',
                label: Icon(Icons.backspace_outlined, color: scheme.onSurfaceVariant, size: 22),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.onTap, required this.label, required this.semanticsLabel});

  final VoidCallback onTap;
  final Widget label;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _keySize,
      height: _keySize,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(label: semanticsLabel, container: true, child: Center(child: label)),
        ),
      ),
    );
  }
}

/// Text field restricted to digits, for setups that prefer typing over the pad.
class PinField extends StatelessWidget {
  const PinField({
    super.key,
    required this.controller,
    required this.maxLength,
    this.label = 'PIN',
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final int maxLength;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      obscuringCharacter: '●',
      keyboardType: TextInputType.number,
      maxLength: maxLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }
}
