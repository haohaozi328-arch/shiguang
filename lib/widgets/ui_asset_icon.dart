import 'package:flutter/material.dart';

class UiAssetIcon extends StatelessWidget {
  const UiAssetIcon(
    this.name, {
    super.key,
    this.size = 22,
    this.fit = BoxFit.contain,
  });

  final String name;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'ui/$name',
      width: size,
      height: size,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.image_not_supported_outlined,
        size: size,
        color: Colors.grey[400],
      ),
    );
  }
}
