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
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.28),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => CustomPaint(
          size: Size(size, size),
          painter: _KeepsakeShieldPainter(),
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
          'Keepsake',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
      ],
    );
  }
}

class _KeepsakeShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final rect = Offset.zero & size;
    final corner = w * 0.23;

    // Background squircle with deep royal indigo gradient
    final bgRRect = RRect.fromRectAndRadius(rect, Radius.circular(corner));
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF6366F1), // Electric Indigo
          Color(0xFF1E1B4B), // Deep Midnight Navy
        ],
      ).createShader(rect);
    canvas.drawRRect(bgRRect, bgPaint);

    // Subtle inner glowing border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025
      ..color = Colors.white.withValues(alpha: 0.25);
    canvas.drawRRect(bgRRect.deflate(w * 0.012), borderPaint);

    // Vault Shield
    final double sw = w * 0.48;
    final double sh = h * 0.56;
    final double left = (w - sw) / 2;
    final double top = (h - sh) / 2 + h * 0.02;
    final double cx = w / 2;

    final shield = Path();
    shield.moveTo(cx, top);
    shield.lineTo(left + sw, top + sh * 0.18);
    shield.lineTo(left + sw, top + sh * 0.52);
    shield.lineTo(cx, top + sh);
    shield.lineTo(left, top + sh * 0.52);
    shield.lineTo(left, top + sh * 0.18);
    shield.close();

    // Shield fill
    final shieldFill = Paint()..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawPath(shield, shieldFill);

    // Shield stroke
    final shieldStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.95);
    canvas.drawPath(shield, shieldStroke);

    // Glowing Keyhole Core
    final double headR = w * 0.075;
    final double keyCenterY = top + sh * 0.42;
    final whitePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    canvas.drawCircle(Offset(cx, keyCenterY - headR * 0.4), headR, whitePaint);

    final double stemW = headR * 0.85;
    final double stemH = headR * 1.3;
    final double stemX = cx - stemW / 2;
    final double stemY = keyCenterY + headR * 0.2;
    canvas.drawRect(Rect.fromLTWH(stemX, stemY, stemW, stemH), whitePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
