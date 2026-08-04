import 'dart:io' show File, Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/gesture/image_horizontal_drag_gesture_recognizer.dart';
import 'package:yuanying/common/widgets/image_viewer/image.dart';
import 'package:yuanying/common/widgets/image_viewer/loading_indicator.dart';
import 'package:yuanying/common/widgets/image_viewer/viewer.dart';
import 'package:yuanying/common/widgets/image_viewer/hero.dart';
import 'package:yuanying/common/widgets/image_viewer/hero_dialog_route.dart';
import 'package:yuanying/utils/extension/num_ext.dart';
import 'package:yuanying/utils/image_utils.dart';
import 'package:yuanying/utils/page_utils.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/utils/utils.dart';
// import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:easy_debounce/easy_throttle.dart';

/// 图片资源模型
class SourceModel {
  final String url;
  final String? liveUrl;
  final bool isLongPic;
  final SourceType sourceType;
  final int? width;
  final int? height;

  const SourceModel({
    required this.url,
    this.liveUrl,
    this.isLongPic = false,
    this.sourceType = SourceType.networkImage,
    this.width,
    this.height,
  });
}

enum SourceType {
  networkImage,
  fileImage,
  livePhoto,
}

/// 大图查看器（PiliPlus 风格）
class GalleryViewer extends StatefulWidget {
  const GalleryViewer({
    super.key,
    this.minScale = 1.0,
    this.maxScale = 8.0,
    required this.quality,
    required this.sources,
    this.initIndex = 0,
    this.onPageChanged,
    this.tag = '',
  });

  final double minScale;
  final double maxScale;
  final int quality;
  final List<SourceModel> sources;
  final int initIndex;
  final ValueChanged<int>? onPageChanged;
  final String tag;

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer>
    with SingleTickerProviderStateMixin {
  late Size _containerSize;
  late final int _quality;
  late final RxInt _currIndex;
  GlobalKey? _key;

  late final PageController _pageController;

  late final TapGestureRecognizer _tapGestureRecognizer;
  late final DoubleTapGestureRecognizer _doubleTapGestureRecognizer;
  late final ImageHorizontalDragGestureRecognizer
      _horizontalDragGestureRecognizer;
  late final LongPressGestureRecognizer _longPressGestureRecognizer;

  late final AnimationController _animateController;
  late final Animation<Color?> _opacityAnimation;
  double dx = 0, dy = 0;

  Offset _offset = Offset.zero;
  bool _dragging = false;

  String _getActualUrl(String url) {
    return _quality != 100 ? ImageUtils.thumbnailUrl(url, _quality) : url;
  }

  @override
  void initState() {
    super.initState();
    _quality = 80;
    _currIndex = widget.initIndex.obs;

    _pageController = PageController(initialPage: widget.initIndex);

    final gestureSettings = MediaQuery.maybeGestureSettingsOf(Get.context!);
    _tapGestureRecognizer = TapGestureRecognizer()
      ..gestureSettings = gestureSettings;
    if (PlatformUtils.isDesktop) {
      _tapGestureRecognizer.onSecondaryTapUp = _showDesktopMenu;
    }
    _doubleTapGestureRecognizer = DoubleTapGestureRecognizer()
      ..onDoubleTap = () {}
      ..gestureSettings = gestureSettings;
    _horizontalDragGestureRecognizer = ImageHorizontalDragGestureRecognizer();
    _longPressGestureRecognizer = LongPressGestureRecognizer()
      ..onLongPress = _onLongPress
      ..gestureSettings = gestureSettings;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _tapGestureRecognizer.onTap = _onTap;
      }
    });

    _animateController = AnimationController(
      duration: const Duration(milliseconds: 750),
      vsync: this,
    );

    _opacityAnimation = _animateController.drive(
      ColorTween(
        begin: Colors.black,
        end: Colors.transparent,
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animateController.dispose();
    _tapGestureRecognizer.dispose();
    _doubleTapGestureRecognizer
      ..onDoubleTapDown = null
      ..onDoubleTap = null
      ..dispose();
    _longPressGestureRecognizer.dispose();
    Future.delayed(const Duration(milliseconds: 200), _currIndex.close);
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _tapGestureRecognizer.addPointer(event);
    _doubleTapGestureRecognizer.addPointer(event);
    _longPressGestureRecognizer.addPointer(event);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 背景色动画（下拉时变透明）
          AnimatedBuilder(
            animation: _animateController,
            builder: (context, child) {
              final color = ColorTween(
                begin: Colors.black,
                end: Colors.transparent,
              ).evaluate(_animateController);
              return ColoredBox(
                color: color ?? Colors.black,
                child: child,
              );
            },
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              _containerSize = constraints.biggest;
              return MatrixTransition(
                animation: _animateController,
                alignment: Alignment.topLeft,
                onTransform: _onTransform,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const ClampingScrollPhysics(),
                  itemCount: widget.sources.length,
                  itemBuilder: _itemBuilder,
                ),
              );
            },
          ),
          _buildIndicator,
        ],
      ),
    );
  }

  Widget get _buildIndicator => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.3),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Obx(
              () => Text(
                "${_currIndex.value + 1}/${widget.sources.length}",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      );

  void _onPageChanged(int index) {
    _currIndex.value = index;
    widget.onPageChanged?.call(index);
  }

  late final ValueChanged<int>? _onChangePage = widget.sources.length == 1
      ? null
      : (int offset) {
          final currPage = _pageController.page?.round() ?? 0;
          final nextPage = (currPage + offset).clamp(
            0,
            widget.sources.length - 1,
          );
          if (nextPage != currPage) {
            _pageController.animateToPage(
              nextPage,
              duration: const Duration(milliseconds: 200),
              curve: Curves.ease,
            );
          }
        };

  Matrix4 _onTransform(double val) {
    final scale = 1.0 + (0.25 - 1.0) * val;
    final tmp = (1.0 - scale) / 2.0;
    return Matrix4.diagonal3Values(scale, scale, scale)..setTranslationRaw(
        _containerSize.width * (val * dx + tmp),
        _containerSize.height * (val * dy + tmp),
        0,
      );
  }

  void _updateMoveAnimation() {
    dy = _offset.dy.sign;
    if (dy == 0) {
      dx = 0;
    } else {
      dx = _offset.dx / _offset.dy.abs();
    }
  }

  void _onDragStart(ScaleStartDetails details) {
    _dragging = true;
    if (_animateController.isAnimating) {
      _animateController.stop();
    } else {
      _offset = Offset.zero;
      _animateController.value = 0.0;
    }
    _updateMoveAnimation();
  }

  void _onDragUpdate(ScaleUpdateDetails details) {
    if (!_dragging || _animateController.isAnimating) {
      return;
    }
    _offset += details.focalPointDelta;
    _updateMoveAnimation();
    if (!_animateController.isAnimating) {
      _animateController.value = _offset.dy.abs() / _containerSize.height;
    }
  }

  void _onDragEnd(ScaleEndDetails details) {
    if (!_dragging || _animateController.isAnimating) {
      return;
    }
    _dragging = false;
    if (!_animateController.isDismissed) {
      if (_animateController.value > 0.2) {
        Get.back();
      } else {
        _animateController.reverse();
      }
    }
  }

  Widget _itemBuilder(BuildContext context, int index) {
    final item = widget.sources[index];
    final Widget child;
    switch (item.sourceType) {
      case SourceType.fileImage:
        child = Image.file(
          key: _key,
          File(item.url),
          filterQuality: FilterQuality.low,
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          containerSize: _containerSize,
          onDragStart: _onDragStart,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
          doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
          horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
          onChangePage: _onChangePage,
        );
      case SourceType.networkImage:
        child = Image(
          key: _key,
          image: NetworkImage(_getActualUrl(item.url)),  // ← 改为 NetworkImage
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          containerSize: _containerSize,
          doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
          horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
          onChangePage: _onChangePage,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              return child;
            }
            if (frame == null) {
              if (widget.quality == _quality) {
                return child;
              } else {
                return Image(
                  image: ResizeImage.resizeIfNeeded(
                    _containerSize.width.toInt(),
                    null,
                    NetworkImage(  // ← 改为 NetworkImage
                      ImageUtils.thumbnailUrl(item.url, widget.quality),
                    ),
                  ),
                  minScale: widget.minScale,
                  maxScale: widget.maxScale,
                  containerSize: _containerSize,
                  onDragStart: null,
                  onDragUpdate: null,
                  onDragEnd: null,
                  doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
                  horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
                  onChangePage: _onChangePage,
                );
              }
            }
            return child;
          },
          loadingBuilder: loadingBuilder,
          onDragStart: _onDragStart,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
        );
      case SourceType.livePhoto:
        child = const SizedBox.shrink();
    }
    return fromHero(tag: '${item.url}${widget.tag}', child: child);
  }

  void _onTap() {
    EasyThrottle.throttle(
      'VIEWER_TAP',
      const Duration(milliseconds: 555),
      Get.back,
    );
  }

  void _onLongPress() {
    final item = widget.sources[_currIndex.value];
    if (item.sourceType == SourceType.fileImage) return;
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // if (PlatformUtils.isDesktop)
            //   ListTile(
            //     onTap: () {
            //       Get.back();
            //       ImageUtils.onShareImg(item.url);
            //     },
            //     dense: true,
            //     title: const Text('分享', style: TextStyle(fontSize: 14)),
            //   ),
            ListTile(
              onTap: () {
                Get.back();
                Utils.copyText(item.url);
              },
              dense: true,
              title: const Text('复制链接', style: TextStyle(fontSize: 14)),
            ),
            ListTile(
              onTap: () {
                Get.back();
                ImageUtils.downloadImg([item.url]);
              },
              dense: true,
              title: const Text('保存图片', style: TextStyle(fontSize: 14)),
            ),
            if (PlatformUtils.isDesktop)
              ListTile(
                onTap: () {
                  Get.back();
                  PageUtils.launchURL(item.url);
                },
                dense: true,
                title: const Text('网页打开', style: TextStyle(fontSize: 14)),
              )
            else if (widget.sources.length > 1)
              ListTile(
                onTap: () {
                  Get.back();
                  ImageUtils.downloadImg(
                    widget.sources.map((item) => item.url).toList(),
                  );
                },
                dense: true,
                title: const Text('保存全部图片', style: TextStyle(fontSize: 14)),
              ),
          ],
        ),
      ),
    );
  }

  void _showDesktopMenu(TapUpDetails details) {
    final item = widget.sources[_currIndex.value];
    if (item.sourceType == SourceType.fileImage) return;
    showMenu(
      context: context,
      position: PageUtils.menuPosition(details.globalPosition),
      items: [
        // PopupMenuItem(
        //   height: 42,
        //   onTap: () => ImageUtils.onShareImg(item.url),
        //   child: const Text('分享', style: TextStyle(fontSize: 14)),
        // ),
        PopupMenuItem(
          height: 42,
          onTap: () => Utils.copyText(item.url),
          child: const Text('复制链接', style: TextStyle(fontSize: 14)),
        ),
        PopupMenuItem(
          height: 42,
          onTap: () => ImageUtils.downloadImg([item.url]),
          child: const Text('保存图片', style: TextStyle(fontSize: 14)),
        ),
        PopupMenuItem(
          height: 42,
          onTap: () => PageUtils.launchURL(item.url),
          child: const Text('网页打开', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
  }

  Widget loadingBuilder(
    BuildContext context,
    Widget child,
    ImageChunkEvent? loadingProgress,
  ) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        child,
        if (loadingProgress != null &&
            loadingProgress.expectedTotalBytes != null &&
            loadingProgress.cumulativeBytesLoaded !=
                loadingProgress.expectedTotalBytes)
          Center(
            child: LoadingIndicator(
              size: 39.4,
              progress:
                  loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!,
            ),
          ),
      ],
    );
  }
}

/// Matrix 过渡组件（用于下拉动画）
class MatrixTransition extends AnimatedWidget {
  const MatrixTransition({
    super.key,
    required Animation<double> animation,
    required this.alignment,
    required this.onTransform,
    required this.child,
  }) : super(listenable: animation);

  final AlignmentGeometry alignment;
  final Matrix4 Function(double) onTransform;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    return Transform(
      transform: onTransform(animation.value),
      alignment: alignment,
      child: child,
    );
  }
}

/// 显示大图查看器（统一入口）
void showImageViewer(
  BuildContext context,
  String imageUrl, {
  String tag = '',
  int quality = 80,
}) {
  if (imageUrl.isEmpty) return;
  Get.to(
    () => GalleryViewer(
      quality: quality,
      sources: [SourceModel(url: imageUrl)],
      initIndex: 0,
      tag: tag,
    ),
    routeName: '/image_viewer',
  );
}