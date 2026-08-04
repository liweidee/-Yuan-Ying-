import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:yuanying/common/widgets/gesture/image_horizontal_drag_gesture_recognizer.dart';
import 'package:yuanying/common/widgets/image_viewer/viewer.dart';

/// 自定义 Image 组件（支持手势和缩放）
class Image extends StatefulWidget {
  const Image({
    super.key,
    required this.image,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.gaplessPlayback = false,
    this.isAntiAlias = false,
    this.filterQuality = FilterQuality.medium,
    required this.minScale,
    required this.maxScale,
    required this.containerSize,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.doubleTapGestureRecognizer,
    required this.horizontalDragGestureRecognizer,
    required this.onChangePage,
  });

  Image.network(
    String src, {
    super.key,
    double scale = 1.0,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.gaplessPlayback = false,
    this.filterQuality = FilterQuality.medium,
    this.isAntiAlias = false,
    Map<String, String>? headers,
    int? cacheWidth,
    int? cacheHeight,
    required this.minScale,
    required this.maxScale,
    required this.containerSize,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.doubleTapGestureRecognizer,
    required this.horizontalDragGestureRecognizer,
    required this.onChangePage,
  }) : image = ResizeImage.resizeIfNeeded(
           cacheWidth,
           cacheHeight,
           NetworkImage(
             src,
             scale: scale,
             headers: headers,
           ),
         ),
       assert(cacheWidth == null || cacheWidth > 0),
       assert(cacheHeight == null || cacheHeight > 0);

  Image.file(
    File file, {
    super.key,
    double scale = 1.0,
    this.frameBuilder,
    this.errorBuilder,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.gaplessPlayback = false,
    this.isAntiAlias = false,
    this.filterQuality = FilterQuality.medium,
    int? cacheWidth,
    int? cacheHeight,
    required this.minScale,
    required this.maxScale,
    required this.containerSize,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.doubleTapGestureRecognizer,
    required this.horizontalDragGestureRecognizer,
    required this.onChangePage,
  }) : assert(
           !kIsWeb,
           'Image.file is not supported on Flutter Web.',
         ),
       image = ResizeImage.resizeIfNeeded(
         cacheWidth,
         cacheHeight,
         FileImage(file, scale: scale),
       ),
       loadingBuilder = null,
       assert(cacheWidth == null || cacheWidth > 0),
       assert(cacheHeight == null || cacheHeight > 0);

  final ImageProvider image;

  final ImageFrameBuilder? frameBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  final double? width;
  final double? height;
  final Color? color;
  final Animation<double>? opacity;
  final FilterQuality filterQuality;
  final BlendMode? colorBlendMode;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final Rect? centerSlice;
  final bool matchTextDirection;
  final bool gaplessPlayback;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final bool isAntiAlias;

  final double minScale;
  final double maxScale;
  final Size containerSize;

  final ValueChanged<ScaleStartDetails>? onDragStart;
  final ValueChanged<ScaleUpdateDetails>? onDragUpdate;
  final ValueChanged<ScaleEndDetails>? onDragEnd;
  final ValueChanged<int>? onChangePage;

  final DoubleTapGestureRecognizer doubleTapGestureRecognizer;
  final ImageHorizontalDragGestureRecognizer horizontalDragGestureRecognizer;

  @override
  State<Image> createState() => _ImageState();
}

class _ImageState extends State<Image> with WidgetsBindingObserver {
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  ImageChunkEvent? _loadingProgress;
  bool _isListeningToStream = false;
  int? _frameNumber;
  bool _wasSynchronouslyLoaded = false;
  Object? _lastException;
  StackTrace? _lastStack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopListeningToStream();
    _replaceImage(info: null);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    _resolveImage();
    _listenToStream();
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(Image oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _resolveImage();
      _listenToStream();
    }
  }

  @override
  void reassemble() {
    _resolveImage();
    super.reassemble();
  }

  void _resolveImage() {
    final ImageStream newStream = widget.image.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );
    _updateSourceStream(newStream);
  }

  ImageStreamListener? _imageStreamListener;
  ImageStreamListener _getListener() {
    _imageStreamListener ??= ImageStreamListener(
      _handleImageFrame,
      onChunk: widget.loadingBuilder == null ? null : _handleImageChunk,
      onError: widget.errorBuilder != null
          ? (Object error, StackTrace? stackTrace) {
              setState(() {
                _lastException = error;
                _lastStack = stackTrace;
              });
            }
          : null,
    );
    return _imageStreamListener!;
  }

  void _handleImageFrame(ImageInfo imageInfo, bool synchronousCall) {
    setState(() {
      _replaceImage(info: imageInfo);
      _loadingProgress = null;
      _lastException = null;
      _lastStack = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
      _wasSynchronouslyLoaded = _wasSynchronouslyLoaded | synchronousCall;
    });
  }

  void _handleImageChunk(ImageChunkEvent event) {
    setState(() {
      _loadingProgress = event;
      _lastException = null;
      _lastStack = null;
    });
  }

  void _replaceImage({required ImageInfo? info}) {
    final ImageInfo? oldImageInfo = _imageInfo;
    if (oldImageInfo != null) {
      SchedulerBinding.instance.addPostFrameCallback(
        (Duration duration) => oldImageInfo.dispose(),
        debugLabel: 'Image.disposeOldInfo',
      );
    }
    _imageInfo = info;
  }

  void _updateSourceStream(ImageStream newStream) {
    if (_imageStream?.key == newStream.key) {
      return;
    }

    if (_isListeningToStream) {
      _imageStream!.removeListener(_getListener());
    }

    if (!widget.gaplessPlayback) {
      setState(() {
        _replaceImage(info: null);
      });
    }

    setState(() {
      _loadingProgress = null;
      _frameNumber = null;
      _wasSynchronouslyLoaded = false;
    });

    _imageStream = newStream;
    if (_isListeningToStream) {
      _imageStream!.addListener(_getListener());
    }
  }

  void _listenToStream() {
    if (_isListeningToStream) {
      return;
    }
    _isListeningToStream = true;
    _imageStream!.addListener(_getListener());
  }

  void _stopListeningToStream() {
    if (!_isListeningToStream) {
      return;
    }
    _imageStream!.removeListener(_getListener());
    _isListeningToStream = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_lastException != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _lastException!, _lastStack);
    }

    final Size childSize;
    if (_imageInfo != null) {
      final imgWidth = _imageInfo!.image.width.toDouble();
      final imgHeight = _imageInfo!.image.height.toDouble();
      childSize = Size(imgWidth, imgHeight);
    } else {
      childSize = Size.zero;
    }

    Widget result = Viewer(
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      isLongPic: false,
      containerSize: widget.containerSize,
      childSize: childSize,
      onDragStart: widget.onDragStart,
      onDragUpdate: widget.onDragUpdate,
      onDragEnd: widget.onDragEnd,
      doubleTapGestureRecognizer: widget.doubleTapGestureRecognizer,
      horizontalDragGestureRecognizer: widget.horizontalDragGestureRecognizer,
      onChangePage: widget.onChangePage,
      child: RawImage(image: _imageInfo?.image),
    );

    if (!widget.excludeFromSemantics) {
      result = Semantics(
        container: widget.semanticLabel != null,
        image: true,
        label: widget.semanticLabel ?? '',
        child: result,
      );
    }

    if (widget.frameBuilder != null) {
      result = widget.frameBuilder!(
        context,
        result,
        _frameNumber,
        _wasSynchronouslyLoaded,
      );
    }

    if (widget.loadingBuilder != null) {
      result = widget.loadingBuilder!(context, result, _loadingProgress);
    }

    return result;
  }
}