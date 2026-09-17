import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../models/alist_file_item.dart';
import '../services/alist_file_utils.dart';
import 'alist_overflow_text.dart';

class AlistFileListItemView extends StatelessWidget {
  final AlistFileItem file;
  final VoidCallback onTap;
  final GestureTapCallback? onMoreIconButtonTap;
  final int? fileNameMaxLines;

  const AlistFileListItemView({
    super.key,
    required this.file,
    required this.onTap,
    this.onMoreIconButtonTap,
    this.fileNameMaxLines,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnail = AlistFileUtils.getCompleteThumbnail(file.thumb);

    String subtitle = file.modified ?? '';
    if (file.sizeDesc != null) {
      subtitle = subtitle.isEmpty ? file.sizeDesc! : '$subtitle - ${file.sizeDesc}';
    }

    return ListTile(
      horizontalTitleGap: 6,
      minVerticalPadding: 12,
      leading: SizedBox(
        width: 40,
        height: 40,
        child: (thumbnail != null && thumbnail.isNotEmpty)
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  thumbnail,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(file.icon, size: 32),
                ),
              )
            : Icon(file.icon, size: 32, color: theme.colorScheme.primary),
      ),
      trailing: _moreIconButton(theme),
      title: _buildTitle(context),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: onTap,
      onLongPress: onMoreIconButtonTap,
    );
  }

  Widget _buildTitle(BuildContext context) {
    final maxLines = fileNameMaxLines ??
        (StorageManager.getSetting<int>(AlistStorageKeys.fileNameMaxLines) ?? 1);
    return maxLines == 1
        ? AlistOverflowText(text: file.name)
        : Text(
            file.name,
            maxLines: maxLines > 2 ? 1000 : 2,
            overflow: TextOverflow.ellipsis,
          );
  }

  Widget _moreIconButton(ThemeData theme) {
    if (onMoreIconButtonTap == null) {
      return Icon(Icons.chevron_right, color: theme.colorScheme.outline);
    }
    return IconButton(
      onPressed: onMoreIconButtonTap,
      icon: Icon(Icons.more_horiz_rounded, color: theme.colorScheme.outline),
    );
  }
}