/// 单条字幕文件（从 zip / gzip / 原始响应中解压得到）
class SubtitleFile {
  /// 文件名（含扩展名）
  final String name;

  /// 原始字节内容
  final List<int> bytes;

  /// 扩展名（小写，不带点，如 srt / ass / vtt / ssa / sub）
  final String ext;

  const SubtitleFile({
    required this.name,
    required this.bytes,
    required this.ext,
  });
}

/// 一次下载可能包含多个文件（如季包 zip）
class SubtitleDownloadResult {
  final List<SubtitleFile> files;
  const SubtitleDownloadResult({required this.files});
}