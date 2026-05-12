import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_responsive.dart';
import 'ui_asset_icon.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItem('首页.png', '首页'),
    _NavItem('笔记.png', '笔记'),
    _NavItem('ai.png', 'AI'),
    _NavItem('设置.png', '设置'),
  ];

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
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: List.generate(_items.length, (i) {
                  final item = _items[i];
                  final on = i == currentIndex;
                  return Expanded(
                    child: _NavBtn(item: item, on: on, onTap: () => onTap(i)),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatefulWidget {
  final _NavItem item;
  final bool on;
  final VoidCallback onTap;
  const _NavBtn({required this.item, required this.on, required this.onTap});

  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn> {
  void _handleTap() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppResponsive.isCompact(context);
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 4),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 10,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: widget.on
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x8CA8EDDA), Color(0x73C2E9FB)],
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: widget.on ? 1.08 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: UiAssetIcon(widget.item.asset, size: compact ? 20 : 22),
            ),
            const SizedBox(height: 4),
            Text(
              widget.item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 8.5 : 9,
                fontWeight: FontWeight.w700,
                color: widget.on ? const Color(0xFF1E6050) : AppColors.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String asset;
  final String label;
  const _NavItem(this.asset, this.label);
}
