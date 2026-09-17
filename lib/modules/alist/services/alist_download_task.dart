import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/alist_download_record.dart';
import '../models/alist_resp_models.dart';
import 'alist_download_manager.dart';
import 'alist_download_task_status.dart';

typedef AlistDownloadTaskStatusCallback = void Function(
  AlistDownloadTask task,
  AlistDownloadTaskStatus status,
  String? reason,
);

class AlistDownloadTask {
  final AlistDownloadManager _downloadManager;
  final String url;
  final AlistDownloadRecord record;
  final CancelToken _cancelToken;
  final AlistDownloadTaskStatusCallback _statusCallback;
  final Map<String, dynamic> requestHeaders;
  final int limitFrequency;
  var _taskMoving = false;
  AlistDownloadTaskStatus _status;
  int? contentLength;
  int downloaded = 0;
  String? failedReason;

  AlistDownloadTask({
    required AlistDownloadManager downloadManager,
    required AlistDownloadTaskStatusCallback statusCallback,
    required this.url,
    required this.requestHeaders,
    required this.record,
    required this.limitFrequency,
    required CancelToken cancelToken,
    AlistDownloadTaskStatus status = AlistDownloadTaskStatus.waiting,
  })  : _cancelToken = cancelToken,
        _downloadManager = downloadManager,
        _statusCallback = statusCallback,
        _status = status;

  AlistDownloadTaskStatus get status => _status;
  bool get taskMoving => _taskMoving;

  void start() async {
    _taskMoving = false;
    if (_recheckCurrentStatus()) return;
    _setCurrentStatus(AlistDownloadTaskStatus.downloading);

    final tmpFile = File('${record.localPath}.tmp');
    final fileDownloadInfo = File('${record.localPath}.downloads');
    AlistDownloadsInfo? downloadsInfo;
    var tmpFileExists = tmpFile.existsSync();
    var downloadInfoFileExists = fileDownloadInfo.existsSync();

    if (tmpFileExists && !downloadInfoFileExists) {
      await tmpFile.delete();
      tmpFileExists = false;
    } else if (!tmpFileExists && downloadInfoFileExists) {
      await fileDownloadInfo.delete();
      downloadInfoFileExists = false;
    } else if (tmpFileExists && downloadInfoFileExists) {
      try {
        final savedJson = await fileDownloadInfo.readAsString();
        final info = AlistDownloadsInfo.fromJson(
            jsonDecode(savedJson) as Map<String, dynamic>);
        if (!info.isSupportRange ||
            tmpFile.lengthSync() > (info.contentLength ?? 0)) {
          await fileDownloadInfo.delete();
          await tmpFile.delete();
          tmpFileExists = false;
          downloadInfoFileExists = false;
        } else if (tmpFile.lengthSync() == (info.contentLength ?? 0)) {
          await _onDownloadFinish(info.decompress, tmpFile, fileDownloadInfo);
          return;
        } else {
          downloadsInfo = info;
        }
      } catch (_) {
        await fileDownloadInfo.delete();
        await tmpFile.delete();
      }
    }

    final requestHeader = Map<String, dynamic>.from(requestHeaders);
    if (downloadsInfo != null && tmpFileExists) {
      requestHeader[HttpHeaders.rangeHeader] =
          'bytes=${tmpFile.lengthSync()}-';
      requestHeader[HttpHeaders.ifRangeHeader] =
          downloadsInfo.etag ?? downloadsInfo.lastModified ?? '';
      downloaded = tmpFile.lengthSync();
    }
    contentLength = downloadsInfo?.contentLength;

    late HttpClientResponse httpResponse;
    try {
      httpResponse = await _downloadManager.request(this, requestHeader);
    } catch (e) {
      _setCurrentStatus(AlistDownloadTaskStatus.failed, reason: e.toString());
      return;
    }
    if (_recheckCurrentStatus()) return;

    final statusCode = httpResponse.statusCode;
    if (statusCode >= 200 && statusCode < 300) {
      final isPartialContent = statusCode == HttpStatus.partialContent;
      final decompress =
          httpResponse.headers.value(HttpHeaders.contentEncodingHeader) ==
              'gzip';
      String? contentLengthStr;
      if (isPartialContent) {
        final range =
            httpResponse.headers.value(HttpHeaders.contentRangeHeader);
        contentLengthStr = range?.split('/').last.trim();
      } else {
        contentLengthStr =
            httpResponse.headers.value(HttpHeaders.contentLengthHeader);
      }
      final eTag = httpResponse.headers.value(HttpHeaders.etagHeader);
      final lastModified =
          httpResponse.headers.value(HttpHeaders.lastModifiedHeader);
      final acceptRanges =
          httpResponse.headers.value(HttpHeaders.acceptRangesHeader);
      final contentLengthInt = int.tryParse(contentLengthStr ?? '') ?? 0;
      final isSupportRange = acceptRanges?.toLowerCase() == 'bytes' &&
          contentLengthStr != null &&
          contentLengthStr.isNotEmpty &&
          contentLengthInt > 0 &&
          ((eTag != null && eTag.isNotEmpty) ||
              (lastModified != null && lastModified.isNotEmpty));
      this.contentLength = contentLengthInt;

      downloaded = isPartialContent ? downloaded : 0;
      if (!isPartialContent) {
        if (tmpFileExists) await tmpFile.delete();
        if (downloadInfoFileExists) await fileDownloadInfo.delete();
      }

      downloadsInfo = AlistDownloadsInfo()
        ..isSupportRange = isSupportRange
        ..contentLength = contentLengthInt
        ..lastModified = lastModified
        ..decompress = decompress
        ..etag = eTag;

      final writeInfoFuture =
          fileDownloadInfo.writeAsString(jsonEncode(downloadsInfo.toJson()));

      Future<void>? asyncWrite;
      late StreamSubscription<List<int>> subscription;
      subscription = httpResponse.listen((event) {
        subscription.pause();
        asyncWrite = tmpFile
            .writeAsBytes(event, mode: FileMode.append)
            .then((_) {
          downloaded += event.length;
          if (!_recheckCurrentStatus()) {
            subscription.resume();
          } else {
            subscription.cancel();
          }
        }).catchError((Object e) async {
          subscription.cancel();
          _setCurrentStatus(AlistDownloadTaskStatus.failed,
              reason: e.toString());
        });
      }, onDone: () async {
        if (!_recheckCurrentStatus()) {
          await asyncWrite;
          await writeInfoFuture;
          await _onDownloadFinish(decompress, tmpFile, fileDownloadInfo);
          _setCurrentStatus(AlistDownloadTaskStatus.finished);
        }
      }, onError: (e) async {
        if (!_recheckCurrentStatus()) {
          _setCurrentStatus(AlistDownloadTaskStatus.failed,
              reason: e.toString());
          await asyncWrite;
        }
      }, cancelOnError: true);
    } else {
      if (!_recheckCurrentStatus()) {
        _setCurrentStatus(AlistDownloadTaskStatus.failed,
            reason: 'statusCode: $statusCode');
      }
    }
  }

  bool _recheckCurrentStatus() {
    if (_cancelToken.isCancelled) {
      _setCurrentStatus(AlistDownloadTaskStatus.canceled);
      return true;
    }
    if (_taskMoving) return true;
    return false;
  }

  void cancel() => _cancelToken.cancel();

  void _setCurrentStatus(AlistDownloadTaskStatus status, {String? reason}) {
    debugPrint('AList-DL status=$status reason=$reason');
    if (status == AlistDownloadTaskStatus.failed) {
      failedReason = reason;
    } else if (failedReason != null) {
      failedReason = null;
    }
    if (_status != status) {
      _status = status;
      _statusCallback(this, status, reason);
    }
  }

  Future<void> _onDownloadFinish(
    bool decompress,
    File tmpFile,
    File fileDownloadInfo,
  ) async {
    final savedFile = File(record.localPath);
    if (savedFile.existsSync()) await savedFile.delete();

    if (decompress) {
      _setCurrentStatus(AlistDownloadTaskStatus.decompressing);
      await tmpFile
          .openRead()
          .transform(gzip.decoder)
          .pipe(savedFile.openWrite());
      await tmpFile.delete();
    } else {
      await tmpFile.rename(record.localPath);
    }

    if (!_cancelToken.isCancelled) {
      _setCurrentStatus(AlistDownloadTaskStatus.finished);
      if (fileDownloadInfo.existsSync()) fileDownloadInfo.delete();
      record.finished = true;
      await _downloadManager.updateRecord(record);
    } else {
      _setCurrentStatus(AlistDownloadTaskStatus.canceled);
    }
  }

  void moveToWaiting() {
    if (_status == AlistDownloadTaskStatus.downloading ||
        _status == AlistDownloadTaskStatus.decompressing) {
      _setCurrentStatus(AlistDownloadTaskStatus.waiting);
      _taskMoving = true;
    }
  }

  void pause() {
    if (_status == AlistDownloadTaskStatus.waiting) {
      _setCurrentStatus(AlistDownloadTaskStatus.paused);
    } else if (_status == AlistDownloadTaskStatus.downloading ||
        _status == AlistDownloadTaskStatus.decompressing) {
      _setCurrentStatus(AlistDownloadTaskStatus.paused);
      _taskMoving = true;
    }
  }
}