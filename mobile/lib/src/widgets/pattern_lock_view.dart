import 'package:flutter/material.dart';

class PatternLockView extends StatefulWidget {
  const PatternLockView({
    super.key,
    required this.onComplete,
    this.dimension = 280,
    this.selectedColor,
    this.dotColor,
  });

  final ValueChanged<String> onComplete;
  final double dimension;
  final Color? selectedColor;
  final Color? dotColor;

  @override
  State<PatternLockView> createState() => _PatternLockViewState();
}

class _PatternLockViewState extends State<PatternLockView> {
  final List<int> _selectedIndices = [];
  Offset? _currentTouch;

  Offset _getDotCenter(int index, double size) {
    final row = index ~/ 3;
    final col = index % 3;
    final cell = size / 3;
    return Offset(col * cell + cell / 2, row * cell + cell / 2);
  }

  int? _findNearestDot(Offset pos, double size) {
    const hitRadius = 36.0;
    for (var i = 0; i < 9; i++) {
      final center = _getDotCenter(i, size);
      final dist = (pos - center).distance;
      if (dist <= hitRadius) return i;
    }
    return null;
  }

  void _handlePanStart(DragStartDetails details) {
    setState(() {
      _selectedIndices.clear();
      final hit = _findNearestDot(details.localPosition, widget.dimension);
      if (hit != null) {
        _selectedIndices.add(hit);
      }
      _currentTouch = details.localPosition;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentTouch = details.localPosition;
      final hit = _findNearestDot(details.localPosition, widget.dimension);
      if (hit != null && !_selectedIndices.contains(hit)) {
        _selectedIndices.add(hit);
      }
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_selectedIndices.isNotEmpty) {
      final pattern = _selectedIndices.join('-');
      widget.onComplete(pattern);
    }
    setState(() {
      _currentTouch = null;
      _selectedIndices.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.selectedColor ?? Theme.of(context).colorScheme.primary;
    final inactiveColor = widget.dotColor ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3);

    return SizedBox(
      width: widget.dimension,
      height: widget.dimension,
      child: GestureDetector(
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: CustomPaint(
          painter: _PatternPainter(
            selectedIndices: List.unmodifiable(_selectedIndices),
            currentTouch: _currentTouch,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.selectedIndices,
    required this.currentTouch,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<int> selectedIndices;
  final Offset? currentTouch;
  final Color activeColor;
  final Color inactiveColor;

  Offset _getDotCenter(int index, Size size) {
    final row = index ~/ 3;
    final col = index % 3;
    final cell = size.width / 3;
    return Offset(col * cell + cell / 2, row * cell + cell / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    final activeDotPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final activeRingPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final linePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw connecting lines
    if (selectedIndices.length > 1) {
      final path = Path();
      final first = _getDotCenter(selectedIndices.first, size);
      path.moveTo(first.dx, first.dy);
      for (var i = 1; i < selectedIndices.length; i++) {
        final pt = _getDotCenter(selectedIndices[i], size);
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // Line to current touch position
    if (selectedIndices.isNotEmpty && currentTouch != null) {
      final last = _getDotCenter(selectedIndices.last, size);
      canvas.drawLine(last, currentTouch!, linePaint);
    }

    // Draw 9 dots
    for (var i = 0; i < 9; i++) {
      final center = _getDotCenter(i, size);
      final isSelected = selectedIndices.contains(i);

      if (isSelected) {
        canvas.drawCircle(center, 12, activeDotPaint);
        canvas.drawCircle(center, 26, activeRingPaint);
      } else {
        canvas.drawCircle(center, 8, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) => true;
}
