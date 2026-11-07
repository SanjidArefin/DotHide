import 'package:flutter/material.dart';

/// A 3x3 drag pattern lock grid.
///
/// The pattern is reported as the ordered list of dot indices (0-8, row major).
/// `setLock` in [LockStore] expects the same list encoded as `"0-1-2"`.
class PatternLock extends StatefulWidget {
  const PatternLock({
    super.key,
    required this.onCompleted,
    this.onChanged,
    this.minLength = 4,
    this.enabled = true,
    this.errorFlash = 0,
  });

  /// Called when the pointer is released with a valid-length pattern.
  final ValueChanged<List<int>> onCompleted;

  /// Called continuously while dragging, so parents can show live feedback.
  final ValueChanged<List<int>>? onChanged;

  final int minLength;
  final bool enabled;

  /// Increment to trigger a red shake, e.g. after a wrong unlock attempt.
  final int errorFlash;

  @override
  State<PatternLock> createState() => _PatternLockState();
}

class _PatternLockState extends State<PatternLock> with SingleTickerProviderStateMixin {
  final List<int> _selected = <int>[];
  Offset? _dragPoint;
  bool _dragging = false;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(covariant PatternLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.errorFlash != oldWidget.errorFlash) {
      _reset();
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _reset() {
    _selected.clear();
    _dragPoint = null;
    _dragging = false;
    widget.onChanged?.call(List<int>.unmodifiable(_selected));
    setState(() {});
  }

  bool _addDotAt(Offset local, Size size, double hitRadius) {
    final geometry = _PatternGeometry(size);
    for (var i = 0; i < 9; i++) {
      if (_selected.contains(i)) continue;
      if ((geometry.centerOf(i) - local).distance <= hitRadius) {
        _selected.add(i);
        widget.onChanged?.call(List<int>.unmodifiable(_selected));
        setState(() {});
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final size = Size(side, side);
        final hitRadius = _PatternGeometry(size).hitRadius;

        return AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = t == 0 ? 0.0 : 10.0 * (1 - t) * (t < 0.5 ? 1 : -1);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.enabled
                ? (details) {
                    _reset();
                    _dragging = true;
                    setState(() => _dragPoint = details.localPosition);
                    _addDotAt(details.localPosition, size, hitRadius);
                  }
                : null,
            onPanUpdate: widget.enabled
                ? (details) {
                    if (!_dragging) return;
                    setState(() => _dragPoint = details.localPosition);
                    _addDotAt(details.localPosition, size, hitRadius);
                  }
                : null,
            onPanEnd: widget.enabled
                ? (_) {
                    _dragging = false;
                    final result = List<int>.unmodifiable(_selected);
                    setState(() => _dragPoint = null);
                    if (result.length >= widget.minLength) {
                      widget.onCompleted(result);
                    } else {
                      _reset();
                    }
                  }
                : null,
            child: CustomPaint(
              size: size,
              painter: _PatternPainter(
                selected: _selected,
                dragPoint: _dragging ? _dragPoint : null,
                activeColor: scheme.onSurface,
                dotColor: scheme.outline,
                trailColor: scheme.onSurfaceVariant,
                fillColor: scheme.surfaceContainerHigh,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PatternGeometry {
  _PatternGeometry(this.size);

  final Size size;

  double get _cell => size.shortestSide / 3;

  double get dotRadius => _cell * 0.14;

  double get hitRadius => _cell * 0.30;

  Offset centerOf(int index) {
    final row = index ~/ 3;
    final col = index % 3;
    return Offset(_cell * (col + 0.5), _cell * (row + 0.5));
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.selected,
    required this.dragPoint,
    required this.activeColor,
    required this.dotColor,
    required this.trailColor,
    required this.fillColor,
  });

  final List<int> selected;
  final Offset? dragPoint;
  final Color activeColor;
  final Color dotColor;
  final Color trailColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _PatternGeometry(size);
    final linePaint = Paint()
      ..color = activeColor
      ..strokeWidth = size.shortestSide * 0.014
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < selected.length - 1; i++) {
      canvas.drawLine(geometry.centerOf(selected[i]), geometry.centerOf(selected[i + 1]), linePaint);
    }
    if (dragPoint != null && selected.isNotEmpty) {
      canvas.drawLine(geometry.centerOf(selected.last), dragPoint!, linePaint);
    }

    for (var i = 0; i < 9; i++) {
      final center = geometry.centerOf(i);
      final isSelected = selected.contains(i);
      canvas.drawCircle(
        center,
        geometry.dotRadius,
        Paint()..color = isSelected ? activeColor : dotColor,
      );
      if (isSelected) {
        canvas.drawCircle(center, geometry.dotRadius * 1.9, Paint()..color = fillColor);
        canvas.drawCircle(
          center,
          geometry.dotRadius * 1.9,
          Paint()
            ..color = trailColor.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.shortestSide * 0.008,
        );
        canvas.drawCircle(center, geometry.dotRadius, Paint()..color = activeColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) =>
      oldDelegate.selected.length != selected.length ||
      oldDelegate.dragPoint != dragPoint ||
      !_sameOrder(oldDelegate.selected, selected);

  static bool _sameOrder(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
