import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';
import 'ui_asset_icon.dart';

class QuickBtns extends StatelessWidget {
  final VoidCallback onVoice;
  const QuickBtns({super.key, required this.onVoice});

  static const _items = [
    _QItem('录音.png', '语音笔记', [Color(0x80A8EDDA), Color(0x5CC2E9FB)]),
    _QItem('笔记.png', '文字笔记', [Color(0x80DDD0FF), Color(0x5CC2D2FF)]),
    _QItem('拍照.png', '拍照记录', [Color(0x80FDD5E8), Color(0x5CFFDCB9)]),
    _QItem('ai.png', 'AI整理', [Color(0x80C2E9FB), Color(0x5CA8EDDA)]),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_items.length, (i) {
        final item = _items[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _items.length - 1 ? 8 : 0),
            child: _QuickBtn(item: item, onTap: i == 0 ? onVoice : null),
          ),
        );
      }),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final _QItem item;
  final VoidCallback? onTap;
  const _QuickBtn({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: item.grad,
        ),
        padding: const EdgeInsets.fromLTRB(5, 12, 5, 10),
        borderRadius: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UiAssetIcon(item.asset, size: 26),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QItem {
  final String asset;
  final String label;
  final List<Color> grad;
  const _QItem(this.asset, this.label, this.grad);
}
