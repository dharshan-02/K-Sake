import 'package:flutter/material.dart';

const keepsakeBrandBlue = Color(0xFF5267C5);

/// The app's consistent mark, drawn in Flutter so it stays crisp at any size.
class KeepsakeLogo extends StatelessWidget {
  const KeepsakeLogo({super.key, this.size = 44, this.showWordmark = false});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE7EAFE),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.shield_rounded,
            size: size * 0.72,
            color: keepsakeBrandBlue,
          ),
          Icon(
            Icons.arrow_forward_rounded,
            size: size * 0.36,
            color: Colors.white,
          ),
        ],
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
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
      ],
    );
  }
}
