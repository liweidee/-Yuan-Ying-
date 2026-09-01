// lib/modules/music/widgets/vinyl_record.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VinylRecordWidget extends StatefulWidget {
  final String? coverUrl;
  final bool isPlaying;

  const VinylRecordWidget({
    super.key,
    this.coverUrl,
    this.isPlaying = false,
  });

  @override
  VinylRecordWidgetState createState() => VinylRecordWidgetState();
}

class VinylRecordWidgetState extends State<VinylRecordWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  ImageProvider? _imageProvider;
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  late ImageStreamListener _imageStreamListener;
  bool _imageLoaded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );

    _rotationAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    );

    if (widget.isPlaying) {
      _animationController.repeat(reverse: false);
    }

    _loadImage();
  }

  void _loadImage() {
    _imageLoaded = false;
    if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty) {
      _imageProvider = CachedNetworkImageProvider(widget.coverUrl!);
      _imageStream = _imageProvider?.resolve(const ImageConfiguration());
      _imageStreamListener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (mounted) {
            setState(() {
              _imageInfo = info;
              _imageLoaded = true;
            });
          }
        },
        onError: (dynamic exception, StackTrace? stackTrace) {
          if (mounted) {
            setState(() {
              _imageLoaded = false;
            });
          }
        },
      );
      _imageStream?.addListener(_imageStreamListener);
    }
  }

  @override
  void didUpdateWidget(covariant VinylRecordWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _animationController.repeat();
      } else {
        _animationController.stop();
      }
    }

    if (widget.coverUrl != oldWidget.coverUrl) {
      _loadImage();
    }
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageStreamListener);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final screenSize = MediaQuery.of(context).size;
        final isLandscape = screenSize.height < screenSize.width;
        final containerSize = isLandscape
            ? constraints.maxWidth * 0.7
            : constraints.maxWidth;
        final recordSize = containerSize * 0.9;

        return Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 左侧封面（小图）
                Container(
                  width: containerSize / 2,
                  height: containerSize,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromARGB(255, 50, 50, 50),
                        offset: Offset(5, 3),
                        blurRadius: 5,
                      ),
                    ],
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    image: _imageInfo != null && _imageLoaded
                        ? DecorationImage(
                            image: _imageProvider!,
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: _imageInfo != null && _imageLoaded
                        ? null
                        : const Color(0xFF2A2A2A),
                  ),
                  child: _imageInfo == null || !_imageLoaded
                      ? const Icon(
                          Icons.music_note,
                          color: Colors.white54,
                          size: 40,
                        )
                      : null,
                ),
                // 右侧黑胶唱片（旋转）
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 0.5,
                    child: RotationTransition(
                      turns: _rotationAnimation,
                      child: CustomPaint(
                        size: Size(recordSize, recordSize),
                        painter: VinylRecordPainter(
                          imageInfo: _imageInfo,
                          imageLoaded: _imageLoaded,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class VinylRecordPainter extends CustomPainter {
  final ImageInfo? imageInfo;
  final bool imageLoaded;

  VinylRecordPainter({
    required this.imageInfo,
    required this.imageLoaded,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 绘制黑胶背景
    final backgroundPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, backgroundPaint);

    // 创建固定随机种子
    final random = Random(12345);

    // 绘制纹路和磨损点
    for (double r = radius * 0.2; r < radius * 0.9; r += 5) {
      final brightness = 1.0 - (r / radius);
      final randomColor = Color.fromRGBO(
        (20 + (r % 30) * brightness).toInt(),
        (20 + (r % 30) * brightness).toInt(),
        (20 + (r % 30) * brightness).toInt(),
        1,
      );

      // 主纹路
      final groovePaint = Paint()
        ..color = randomColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = (1 + (r % 3) / 3);
      canvas.drawCircle(center, r, groovePaint);

      // 添加磨损点
      const angleStep = 2 * pi / 3;
      final baseAngle = random.nextDouble() * 2 * pi;
      for (int i = 0; i < 8; i++) {
        if (random.nextDouble() > 0.6) continue;

        final angle = baseAngle + i * angleStep + random.nextDouble() * 0.2 - 0.1;
        final dotRadius = r + random.nextDouble() * 4 - 2;
        final position = Offset(
          center.dx + dotRadius * cos(angle),
          center.dy + dotRadius * sin(angle),
        );

        final dotPaint = Paint()
          ..color = randomColor.withOpacity(0.8)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(
          position,
          1.5 + random.nextDouble() * 1.5,
          dotPaint,
        );
      }
    }

    // 专辑封面（中心圆形）
    final coverRadius = radius * 0.25;
    final coverRect = Rect.fromCircle(center: center, radius: coverRadius);
    final path = Path()..addOval(coverRect);
    canvas.clipPath(path);

    if (imageInfo != null && imageLoaded) {
      final sourceSize = Size(
        imageInfo!.image.width.toDouble(),
        imageInfo!.image.height.toDouble(),
      );
      final fitted = applyBoxFit(BoxFit.cover, sourceSize, coverRect.size);
      final sourceRect = Alignment.center.inscribe(fitted.source, Offset.zero & sourceSize);
      final destRect = Alignment.center.inscribe(fitted.destination, coverRect);

      canvas.drawImageRect(imageInfo!.image, sourceRect, destRect, Paint());
    } else {
      // 无封面时显示默认图标
      final fallbackPaint = Paint()
        ..color = const Color(0xFF3A4356)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, coverRadius, fallbackPaint);

      final textPainter = TextPainter(
        text: const TextSpan(
          text: '♫',
          style: TextStyle(
            color: Colors.white,
            // fontSize 改为非 const，因为 coverRadius * 0.6 是运行时计算的
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      // 单独设置 fontSize
      textPainter.text = TextSpan(
        text: '♫',
        style: TextStyle(
          color: Colors.white,
          fontSize: coverRadius * 0.6,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant VinylRecordPainter oldDelegate) {
    return oldDelegate.imageInfo != imageInfo || oldDelegate.imageLoaded != imageLoaded;
  }
}