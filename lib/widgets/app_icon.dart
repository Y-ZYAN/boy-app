import 'dart:typed_data';
import 'package:flutter/material.dart';

/// App 图标组件：优先展示真实图标，失败回退首字母头像
class AppIcon extends StatelessWidget {
  final String appName;
  final String packageName;
  final IconCache icons;
  final bool active;

  const AppIcon({
    super.key,
    required this.appName,
    required this.packageName,
    required this.icons,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconBytes = icons[packageName];
    if (iconBytes != null && iconBytes.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: Image.memory(
            iconBytes,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallback(context),
          ),
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    return CircleAvatar(
      backgroundColor: active
          ? Colors.green.withValues(alpha: 0.15)
          : Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        appName.isNotEmpty ? appName[0].toUpperCase() : '?',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: active
              ? Colors.green
              : Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// App 图标缓存（包名 → PNG 字节数组）
typedef IconCache = Map<String, Uint8List?>;
