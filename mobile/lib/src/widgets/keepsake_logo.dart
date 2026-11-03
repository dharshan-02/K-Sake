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
      padding: EdgeInsets.all(size * 0.10),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => CustomPaint(
          size: Size(size, size),
          painter: _PremiumKSPainter(),
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

class _PremiumKSPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512.0;
    final strokeW = 42.0 * scale;

    final penCyan = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final penBlue = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final penIndigo = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // --- Letter K ---
    final kX = 142.0 * scale;
    final kTopY = 132.0 * scale;
    final kBotY = 380.0 * scale;
    final kMidY = 256.0 * scale;

    canvas.drawLine(Offset(kX, kTopY), Offset(kX, kBotY), penBlue);

    final kArmTopX = 248.0 * scale;
    final kArmTopY = 132.0 * scale;
    canvas.drawLine(Offset(kX, kMidY), Offset(kArmTopX, kArmTopY), penCyan);

    final kArmBotX = 248.0 * scale;
    final kArmBotY = 380.0 * scale;
    canvas.drawLine(
      Offset(kX + 16.0 * scale, kMidY + 12.0 * scale),
      Offset(kArmBotX, kArmBotY),
      penIndigo,
    );

    // --- Letter S ---
    final sLeft = 280.0 * scale;
    final sRight = 395.0 * scale;
    final sWidth = sRight - sLeft;
    final sTop = 132.0 * scale;
    final sMid = 256.0 * scale;
    final loopH = 126.0 * scale;

    final sTopPath = Path()
      ..addArc(Rect.fromLTWH(sLeft, sTop, sWidth, loopH), 0, -3.4)
      ..lineTo(sRight - 8.0 * scale, sMid + 28.0 * scale);
    canvas.drawPath(sTopPath, penCyan);

    final sBotPath = Path()
      ..moveTo(sLeft + 14.0 * scale, sMid + 16.0 * scale)
      ..lineTo(sRight - 2.0 * scale, sMid + 32.0 * scale)
      ..addArc(Rect.fromLTWH(sLeft, sMid - 2.0 * scale, sWidth, loopH), 0.35, 3.4);
    canvas.drawPath(sBotPath, penIndigo);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
