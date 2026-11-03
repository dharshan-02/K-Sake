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
      padding: EdgeInsets.all(size * 0.14),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const FlutterLogo(),
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
