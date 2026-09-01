// lib/modules/music/utils/clear_html_tags.dart

/// 将 mm:ss 格式的时间转换为秒
int duration2seconds(String durationStr) {
  if (durationStr.isEmpty) return 0;
  final parts = durationStr.split(':');
  if (parts.length < 2) return 0;
  final minutes = int.tryParse(parts[0]) ?? 0;
  final seconds = int.tryParse(parts[1]) ?? 0;
  return minutes * 60 + seconds;
}

/// 将秒数转换为 mm:ss 格式
String seconds2duration(int seconds) {
  final minutes = (seconds / 60).floor();
  final remainingSeconds = seconds % 60;
  final minutesStr = minutes.toString().padLeft(2, '0');
  final secondsStr = remainingSeconds.toString().padLeft(2, '0');
  return '$minutesStr:$secondsStr';
}

/// 清理 HTML 标签
String clearHtmlTags(String htmlText) {
  final exp = RegExp(r'<[^>]*>', multiLine: true, caseSensitive: true);
  return htmlText
      .replaceAll(exp, '')
      .replaceAll(RegExp(r'&nbsp;|&amp;'), ' ')
      .replaceAll(RegExp(r'】'), '-')
      .replaceAll('【', '');
}