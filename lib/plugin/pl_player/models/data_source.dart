import 'package:path/path.dart' as path;

const String _videoNameMp4 = 'video.mp4';
const String _videoNameM3u8 = 'video.m3u8';
const String _audioNameM4a = 'audio.m4a';

sealed class DataSource {
  final String videoSource;
  final String? audioSource;
  final Map<String, String>? headers;  // 新增

  DataSource({
    required this.videoSource,
    required this.audioSource,
    this.headers,
  });
}

class NetworkSource extends DataSource {
  NetworkSource({
    required super.videoSource,
    required super.audioSource,
    super.headers,
  });
}

class FileSource extends DataSource {
  final String dir;
  final bool isMp4;

  FileSource({
    required this.dir,
    required this.isMp4,
    required bool hasDashAudio,
    required String typeTag,
  }) : super(
         videoSource: path.join(dir, typeTag,
            isMp4 ? _videoNameMp4 : _videoNameM3u8),
          audioSource: isMp4 || !hasDashAudio
            ? null
            : path.join(dir, typeTag, _audioNameM4a),
          headers: null, // 本地文件无需headers
       );
}