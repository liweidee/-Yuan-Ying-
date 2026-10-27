// lib/modules/web_tab/widgets/web_tab_topbar.dart
import 'package:flutter/material.dart';

class WebTabTopBar extends StatelessWidget {
  final String sourceName;
  final String pageTitle;
  final String pageUrl;
  final bool isLoading;
  final double progress;
  final VoidCallback onSwitchSource;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback onReload;
  final VoidCallback onFullscreen;
  final VoidCallback onMenu;

  const WebTabTopBar({
    super.key,
    required this.sourceName,
    required this.pageTitle,
    required this.pageUrl,
    required this.isLoading,
    required this.progress,
    required this.onSwitchSource,
    this.onBack,
    this.onForward,
    required this.onReload,
    required this.onFullscreen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface);

    return Container(
      color: bg,
      padding: EdgeInsets.only(
        top: MediaQuery.viewPaddingOf(context).top + 4,
        left: 8,
        right: 4,
        bottom: 6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          isLoading
              ? LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                )
              : const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onSwitchSource,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.language,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      sourceName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.arrow_drop_down,
                                      size: 18,
                                      color: cs.onSurface
                                          .withValues(alpha: 0.6)),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                pageTitle.isNotEmpty
                                    ? pageTitle
                                    : (pageUrl.isNotEmpty ? pageUrl : '—'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _btn(Icons.chevron_left, onBack),
              _btn(Icons.chevron_right, onForward),
              _btn(Icons.refresh, onReload),
              _btn(Icons.fullscreen, onFullscreen),
              _btn(Icons.apps, onMenu),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback? onTap) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
    );
  }
}