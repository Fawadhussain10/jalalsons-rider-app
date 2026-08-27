import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class JSLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final String? text;
  final TextStyle? textStyle;
  final bool showShadow;

  const JSLogo({
    super.key,
    this.size = 60.0,
    this.showText = false,
    this.text,
    this.textStyle,
    this.showShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // JS Logo Image
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: showShadow
                ? [
                    BoxShadow(
                      color: AppColors.jsRed.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 3,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/logos/JS_rider_logo.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
        ),
        // Optional text below logo
        if (showText && text != null) ...[
          const SizedBox(height: 8),
          Text(
            text!,
            style: textStyle ??
                TextStyle(
                  color: AppColors.jsRed,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
          ),
        ],
      ],
    );
  }
}

class JSLogoSmall extends StatelessWidget {
  final double size;
  final bool showBorder;

  const JSLogoSmall({
    super.key,
    this.size = 32.0,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(color: AppColors.jsWhite, width: 2)
            : null,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/logos/JS_rider_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class JSLogoWithGradient extends StatelessWidget {
  final double size;
  final bool showShadow;
  final bool showGlow;

  const JSLogoWithGradient({
    super.key,
    this.size = 80.0,
    this.showShadow = true,
    this.showGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.jsRed.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
                if (showGlow)
                  BoxShadow(
                    color: AppColors.jsRed.withOpacity(0.6),
                    blurRadius: 30,
                    spreadRadius: 10,
                    offset: const Offset(0, 0),
                  ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/logos/JS_rider_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}


