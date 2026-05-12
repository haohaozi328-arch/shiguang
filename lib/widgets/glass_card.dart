import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double blurSigma;
  final List<BoxShadow>? boxShadow;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 23,
    this.backgroundColor,
    this.borderColor,
    this.blurSigma = 1,
    this.boxShadow,
    this.gradient,
    this.onTap,
    this.width,
    this.height,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: gradient,
            color: gradient == null
                ? (backgroundColor ?? AppColors.glass)
                : null,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? AppColors.glassLine,
              width: 1.5,
            ),
            boxShadow:
                boxShadow ??
                const [
                  BoxShadow(
                    color: Color(0x308E8E8E),
                    blurRadius: 15,
                    offset: Offset(0, 6),
                  ),
                ],
          ),
          child: padding != null
              ? Padding(padding: padding!, child: child)
              : child,
        ),
      ),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }
    if (onTap != null) {
      card = GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

class GlassCard2 extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  const GlassCard2({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: borderRadius,
      padding: padding,
      backgroundColor: backgroundColor ?? AppColors.glass2,
      borderColor: borderColor ?? AppColors.glassLine,
      blurSigma: 1,
      boxShadow:
          boxShadow ??
          const [
            BoxShadow(
              color: Color(0x308E8E8E),
              blurRadius: 15,
              offset: Offset(0, 6),
            ),
          ],
      child: child,
    );
  }
}

class GlassBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0x0FFFFFFF),
            border: Border(top: BorderSide(color: Color(0x4DD1D5DB), width: 1)),
            boxShadow: [
              BoxShadow(
                color: Color(0x308E8E8E),
                blurRadius: 15,
                offset: Offset(0, -2),
              ),
            ],
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
