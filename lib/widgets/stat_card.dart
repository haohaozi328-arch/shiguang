import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_responsive.dart';
import 'glass_card.dart';
import 'ui_asset_icon.dart';

class StatCard extends StatelessWidget {
  final String iconAsset;
  final String label, value, sub;
  final List<Color> bar, grad;
  final double barW;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.value,
    required this.sub,
    required this.bar,
    required this.barW,
    required this.grad,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final compact = AppResponsive.isCompact(context);
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: grad,
        ),
        padding: EdgeInsets.fromLTRB(12, compact ? 10 : 12, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 24 : 28,
              height: compact ? 24 : 28,
              child: UiAssetIcon(iconAsset, size: compact ? 24 : 28),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub,
                letterSpacing: 0,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: AppColors.textDark,
                height: 1,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.textSub),
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (ctx, con) => Container(
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x1A648CC8),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: barW,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: bar),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
