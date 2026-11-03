import 'package:flutter/material.dart';

class KeepsakeLogo extends StatelessWidget {
  const KeepsakeLogo({
    super.key,
    this.size = 40,
    this.showWordmark = false,
  });

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: (size * 0.02).clamp(1.0, 2.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.04),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.12),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => CustomPaint(
          size: Size(size, size),
          painter: _KSMonogramPainter(),
        ),
      ),
    );

    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Text(
          'Keep Safe',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
      ],
    );
  }
}

class _KSMonogramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512.0;
    final strokeW = 36.0 * scale;

    final penLight = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final penMid = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final penDark = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // --- Letter K ---
    final kX = 140.0 * scale;
    final kTopY = 140.0 * scale;
    final kBotY = 372.0 * scale;
    canvas.drawLine(Offset(kX, kTopY), Offset(kX, kBotY), penMid);

    final kMidY = 256.0 * scale;
    final kArmTopX = 236.0 * scale;
    final kArmTopY = 140.0 * scale;
    canvas.drawLine(Offset(kX, kMidY), Offset(kArmTopX, kArmTopY), penLight);

    final kArmBotX = 236.0 * scale;
    final kArmBotY = 372.0 * scale;
    canvas.drawLine(
      Offset(kX + 14.0 * scale, kMidY + 8.0 * scale),
      Offset(kArmBotX, kArmBotY),
      penDark,
    );

    // --- Letter S ---
    final sLeft = 285.0 * scale;
    final sRight = 385.0 * scale;
    final sTop = 140.0 * scale;
    final sMid = 256.0 * scale;
    final arcH = 116.0 * scale;

    final sTopHalf = Path()
      ..addArc(
        Rect.fromLTWH(sLeft, sTop, sRight - sLeft, arcH),
        0.35,
        -3.5,
      )
      ..lineTo(sRight - 12.0 * scale, sMid + 25.0 * scale);
    canvas.drawPath(sTopHalf, penLight);

    final sBotHalf = Path()
      ..moveTo(sLeft + 12.0 * scale, sMid + 15.0 * scale)
      ..lineTo(sRight - 10.0 * scale, sMid + 30.0 * scale)
      ..addArc(
        Rect.fromLTWH(sLeft, sMid - 6.0 * scale, sRight - sLeft, arcH),
        3.5,
        -3.5,
      );
    canvas.drawPath(sBotHalf, penDark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
