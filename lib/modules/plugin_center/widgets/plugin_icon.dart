// lib/modules/plugin_center/widgets/plugin_icon.dart

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';

class PluginIcon extends StatelessWidget {
  final String id;
  final String? icon;
  final String indexBaseUrl;
  final double size;

  const PluginIcon({
    super.key,
    required this.id,
    required this.icon,
    required this.indexBaseUrl,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<String?>(
      future: PluginPaths.resolveIcon(
        icon: icon,
        indexBaseUrl: indexBaseUrl,
      ),
      builder: (context, snap) {
        final resolved = snap.data;
        if (resolved != null && resolved.isNotEmpty) {
          if (resolved.startsWith('http')) {
            return ClipRRect(
              borderRadius: Style.mdRadius,
              child: Image.network(
                resolved,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(colorScheme),
              ),
            );
          }
          return ClipRRect(
            borderRadius: Style.mdRadius,
            child: Image.file(
              File(resolved),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(colorScheme),
            ),
          );
        }
        return _fallback(colorScheme);
      },
    );
  }

  Widget _fallback(ColorScheme colorScheme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: Style.mdRadius,
      ),
      child: Icon(
        _iconForPlugin(id),
        color: colorScheme.primary,
        size: size * 0.5,
      ),
    );
  }

  IconData _iconForPlugin(String id) {
    switch (id) {
      case 'nodejs-win':
        return Icons.javascript;
      case 'php-win':
        return Icons.code;
      case 'python-win':
        return Icons.terminal;
      case 'qjs-win':
        return Icons.bolt;
      case 'mediaProxy-win':
        return Icons.cast_connected;
      default:
        return Icons.extension;
    }
  }
}