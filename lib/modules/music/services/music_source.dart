import 'dart:async';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart';
import 'package:just_audio/just_audio.dart';
import 'package:yuanying/t4/models/video_detail.dart';

class MusicSource extends StreamAudioSource {
  final List<int> _bytes = [];
  int _sourceLength = 0;
  String _contentType = "audio/mpeg";
  final String _url;
  final Map<String, String>? _headers;
  bool _isInit = false;

  @override
  MediaItem get tag {
    return MediaItem(
      id: _url,
      title: '音频',
    );
  }

  Future<StreamedResponse> getMusicStream(
    String url,
    Map<String, String>? headers,
    Function(List<int> data) callback,
  ) async {
    final completer = Completer<StreamedResponse>();

    final request = Request("GET", Uri.parse(url));
    if (headers != null) {
      request.headers.addAll(headers);
    }
    final client = Client();
    client.send(request).then((response) {
      var isStart = false;
      response.stream.listen((List<int> data) {
        callback(data);
        if (!isStart) {
          completer.complete(response);
          isStart = true;
        }
      }, onError: (error) {
        completer.completeError(error);
      });
    }).catchError((error) {
      completer.completeError(error);
    });

    return completer.future;
  }

  MusicSource(this._url, {Map<String, String>? headers})
      : _headers = headers;

  _init() async {
    if (_isInit) return;
    var resp = await getMusicStream(_url, _headers, (List<int> data) {
      _bytes.addAll(data);
    });
    _sourceLength = resp.contentLength ?? 0;
    _contentType = resp.headers["content-type"] ?? "audio/mpeg";
    _isInit = true;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    await _init();
    start ??= 0;
    end ??= _bytes.length;

    // 轮询等待数据
    while (_bytes.length < end) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    return StreamAudioResponse(
      sourceLength: _sourceLength,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: _contentType,
    );
  }
}