import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 多线程分片下载器
///
/// 修复记录（相对于出问题的版本）：
///
/// 1. [致命] 僵尸任务：客户端断开检测只依赖 response.done + add() 抛异常，
///    一旦泵送器卡住就再也检测不到断开，旧任务会继续把几百 MB 全量下完。
///    现在改为 response.addStream() + response.done + 停滞看门狗三重检测。
///
/// 2. [致命] 背压失效：旧版手动 listen 且从不 pause 订阅，
///    StreamController 的 onPause/onResume 永远不触发，_consumerPaused 恒为
///    false，worker 全速下载把数据堆在内存里。现在改回 addStream，由 IOSink
///    在 socket 写满时暂停源流，形成真正的背压闭环。
///
/// 3. [致命] 有序队列空洞死锁：worker 重试 5 次失败后直接 return，
///    它领走的分片永远进不了 _orderedBuffer，泵送器永久等待，
///    run() 里的 while(_pumpRunning) 跟着 50ms 死循环。
///    现在失败即标记 _failed 并让泵送器退出。
///
/// 4. [严重] 槽位泄漏：_acquireSlot() 之后 if(!_running) return 没有释放槽位，
///    槽位耗尽后其余 worker 永久等待。已修复。
class ConcurrentDownloader {
  ConcurrentDownloader({
    required this.url,
    required this.headers,
    required this.startOffset,
    required this.endOffset,
    required this.chunkSize,
    required this.threadCount,
    required this.maxBufferedChunks,
    required this.dio,
    required this.log,
    this.stallTimeout = const Duration(seconds: 60),
  });

  final String url;
  final Map<String, String> headers;
  final int startOffset;
  final int endOffset;
  final int chunkSize;
  final int threadCount;
  final int maxBufferedChunks;
  final Dio dio;
  final void Function(String) log;

  /// 连续这么久没有任何分片完成 / 没有任何字节推进，就判定为停滞并自杀
  final Duration stallTimeout;

  // ---- 运行时状态 ----
  int _nextChunkStart = 0;
  bool _running = false;
  bool _consumerPaused = false;
  Completer<void>? _resumeCompleter;

  /// 失败原因；非空即代表本次下载已判死
  String? _failReason;
  bool get hasFailed => _failReason != null;

  final _cancelToken = CancelToken();

  // ---- 背压计数 ----
  int _pendingCount = 0;
  final _waitingWorkers = <Completer<void>>[];

  // ---- 停滞看门狗 ----
  int _lastProgressAt = 0;
  int _completedChunks = 0;
  Timer? _stallTimer;

  // ---- 输出流 ----
  late StreamController<Uint8List> _controller;

  // ---- 有序队列 ----
  final _orderedBuffer = SplayTreeMap<int, Uint8List>();
  int _nextExpectedOffset = 0;
  Completer<void>? _pumpSignal;
  bool _pumpRunning = false;

  bool get isCancelled => _cancelToken.isCancelled;

  void _touchProgress() {
    _lastProgressAt = DateTime.now().millisecondsSinceEpoch;
  }

  /// 启动下载并把数据流写入 HTTP 响应。
  Future<void> run(HttpResponse response) async {
    _running = true;
    _nextExpectedOffset = startOffset;
    _nextChunkStart = startOffset;
    _touchProgress();

    _controller = StreamController<Uint8List>(
      onPause: () {
        _consumerPaused = true;
      },
      onResume: () {
        _consumerPaused = false;
        final completer = _resumeCompleter;
        _resumeCompleter = null;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      },
      onCancel: () {
        _shutdown('consumer cancelled');
      },
    );

    // ---- 停滞看门狗：客户端静默断开时最可靠的兜底 ----
    //
    // 注意：缓冲区被打满说明是「客户端读得慢」而不是「卡死」，
    // 这种情况绝不能杀，否则正常播放会被误伤。
    _stallTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_running || _failReason != null) return;
      if (_pendingCount >= maxBufferedChunks) return; // 背压中，正常
      final idle = DateTime.now().millisecondsSinceEpoch - _lastProgressAt;
      if (idle > stallTimeout.inMilliseconds) {
        log('[Downloader] 停滞 ${idle}ms 无进展（pending=$_pendingCount），主动放弃');
        _shutdown('stalled ${idle}ms');
      }
    });

    // ============================================================
    // 首片预加载：同步下载第一片并写入流
    // ============================================================
    try {
      final firstStart = startOffset;
      final firstEnd = _gridEnd(firstStart);

      final firstData = await _downloadRange(firstStart, firstEnd);
      if (!_running) {
        await _controller.close();
        try {
          await response.close();
        } catch (_) {}
        return;
      }

      // 首片直接写入响应，让播放器立刻拿到 HTTP 头 + 头部分字节
      response.add(firstData);
      _nextExpectedOffset = firstEnd + 1;
      _nextChunkStart = firstEnd + 1;
      _touchProgress();

      log('[Downloader] 首片预加载完成: $firstStart-$firstEnd '
          '(${firstData.length} bytes)');
    } catch (e) {
      log('[Downloader] 首片下载失败: $e');
      _shutdown('first chunk failed: $e');
      await _controller.close();
      try {
        await response.close();
      } catch (_) {}
      return;
    }

    // ============================================================
    // 关键修复：用 response.addStream() 而不是手动 listen
    //
    // addStream 内部会在 socket 写缓冲满时暂停源流，从而触发
    // StreamController.onPause -> _consumerPaused = true -> worker 暂停下载，
    // 这才是真正的背压闭环。手动 listen 时订阅者从不 pause，背压形同虚设。
    // ============================================================
    final finished = Completer<void>();
    void finish() {
      if (!finished.isCompleted) finished.complete();
    }

    response.addStream(_controller.stream).then((_) {
      _touchProgress();
      finish();
    }).catchError((Object e) {
      log('[Downloader] 写入响应失败（客户端可能已断开）: $e');
      _shutdown('write failed: $e');
      finish();
    });

    // 客户端断开：response.done 会以 error 完成
    response.done.then((_) {
      finish();
    }).catchError((Object e) {
      log('[Downloader] response.done 异常（客户端断开）: $e');
      _shutdown('client disconnected');
      finish();
    });

    // ---- 启动 N 个 worker ----
    // 必须先 generate worker（_activeWorkers 会同步自增），再启动泵送器；
    // 否则泵送器第一次循环就看到 _activeWorkers == 0 而误判"全部结束"直接退出。
    final workers = List<Future<void>>.generate(
      threadCount,
      (_) => _worker(),
      growable: false,
    );

    // ---- 启动泵送器 ----
    _pumpRunning = true;
    unawaited(_pump());

    await Future.wait(workers);

    // 唤醒泵送器处理剩余数据
    _pumpSignal?.complete();
    _pumpSignal = null;

    // 等待泵送器退出（带上限，杜绝 while(true) 死等）
    final pumpDeadline = DateTime.now().millisecondsSinceEpoch + 10000;
    while (_pumpRunning &&
        _orderedBuffer.isNotEmpty &&
        DateTime.now().millisecondsSinceEpoch < pumpDeadline) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    if (_pumpRunning && _orderedBuffer.isNotEmpty) {
      log('[Downloader] 泵送器超时未排空，强制结束');
      _shutdown('pump timeout');
    }

    if (!_controller.isClosed) {
      await _controller.close();
    }

    // 三路竞速：正常写完 / 客户端断开 / 被判死或被外部取消
    unawaited(_failWatcher().then((_) => finish()));
    await finished.future;

    try {
      await response.flush();
      await response.close();
    } catch (_) {}

    _shutdownIfStillRunning('finished');
    log('[Downloader] 结束: 分片=$_completedChunks');
  }

  /// 失败观察者：一旦 _failReason 被置位就立刻完成，让 run() 退出
  Future<void> _failWatcher() async {
    while (_running && _failReason == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _shutdownIfStillRunning(String reason) {
    if (_running) {
      _running = false;
      log('[Downloader] 关闭: $reason');
      _cancelStallTimer();
      if (!_cancelToken.isCancelled) {
        _cancelToken.cancel(reason);
      }
      _wakeAll();
      _orderedBuffer.clear();
    }
  }

  void _cancelStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  // ================================================================
  // 泵送器
  // ================================================================

  Future<void> _pump() async {
    _pumpRunning = true;
    try {
      while (_running && _failReason == null) {
        final data = _orderedBuffer.remove(_nextExpectedOffset);

        if (data != null) {
          if (!_controller.isClosed) {
            _controller.add(data);
          }
          _nextExpectedOffset += data.length;
          _completedChunks++;
          _touchProgress();
          _releaseSlot();
          continue;
        }

        // 缓冲区空了：如果所有 worker 都退出了且没有待处理分片，就该收尾
        if (_allWorkersDone()) {
          break;
        }

        _pumpSignal = Completer<void>();
        await _pumpSignal!.future;
      }
    } catch (e) {
      log('[Downloader] 泵送器异常: $e');
    } finally {
      _pumpRunning = false;
    }
  }

  bool _allWorkersDone() => _activeWorkers == 0 && _orderedBuffer.isEmpty;

  // ================================================================
  // Worker
  // ================================================================

  int _activeWorkers = 0;

  Future<void> _worker() async {
    _activeWorkers++;
    try {
      while (_running && _failReason == null) {
        // ---- 1. 认领下一片（await 前同步执行，Dart 单线程下原子） ----
        // 认领到下一个网格边界：既保证与上一片严格首尾相接（有序队列无空洞），
        // 也让分片划分与 startOffset 无关（同一 URL 从不同位置读，划分一致）。
        final start = _nextChunkStart;
        if (start > endOffset) return;
        final end = _gridEnd(start);
        _nextChunkStart = end + 1;

        // ---- 2. 背压：等待缓冲区槽位 ----
        // 修复原版：这里原来 await 之后直接 return，槽位没释放，
        // 泄漏够多之后其余 worker 会全部永久卡在 _acquireSlot。
        final gotSlot = await _acquireSlot();
        if (!gotSlot || !_running || _failReason != null) {
          if (gotSlot) _releaseSlot();
          return;
        }

        // ---- 3. 等待消费者恢复 ----
        await _waitIfPaused();
        if (!_running || _failReason != null) {
          _releaseSlot();
          return;
        }

        // ---- 4. 下载 ----
        Uint8List? data;
        for (int retry = 0; retry < 5 && _running && _failReason == null; retry++) {
          try {
            data = await _downloadRange(start, end);
            break;
          } on DioException catch (e) {
            if (CancelToken.isCancel(e)) {
              _releaseSlot();
              return;
            }
            log('[Downloader] 分片 $start-$end 第 ${retry + 1} 次失败: $e');
            await Future.delayed(Duration(milliseconds: 500 * (retry + 1)));
          } catch (e) {
            log('[Downloader] 分片 $start-$end 第 ${retry + 1} 次失败: $e');
            await Future.delayed(Duration(milliseconds: 500 * (retry + 1)));
          }
        }

        // ---- 5. 失败即判死：绝不能在有序队列里留下永久空洞 ----
        if (data == null || data.isEmpty) {
          _releaseSlot();
          if (_running) {
            log('[Downloader] 分片 $start 彻底失败，结束本次下载');
            _shutdown('chunk $start failed');
          }
          return;
        }
        if (!_running) {
          _releaseSlot();
          return;
        }

        try {
          if (_controller.isClosed) {
            _releaseSlot();
            return;
          }
          _orderedBuffer[start] = data;
          _touchProgress();

          _pumpSignal?.complete();
          _pumpSignal = null;
        } catch (e) {
          log('[Downloader] 缓冲区写入失败: $e');
          _releaseSlot();
          return;
        }
      }
    } finally {
      _activeWorkers--;
      // 唤醒可能正在空等的泵送器
      _pumpSignal?.complete();
      _pumpSignal = null;
    }
  }

  // ================================================================
  // 分片下载
  // ================================================================

  /// 本片下载的结束偏移：下一个「全局 chunk 网格」边界（不超过 endOffset）
  int _gridEnd(int start) {
    final gridEnd = (start ~/ chunkSize) * chunkSize + chunkSize - 1;
    return gridEnd > endOffset ? endOffset : gridEnd;
  }

  /// 下载 [start, limitEnd]（limitEnd 必须是网格边界或 endOffset）。
  Future<Uint8List> _downloadRange(int start, int limitEnd) async {
    // 分片按「全局 chunk 网格」对齐：即使 start 不是 chunkSize 的整数倍，
    // 也统一从 (start ~/ chunkSize) * chunkSize 处取，保证与上一次请求
    // 的划分边界一致（同一 URL 无论从哪里开始读，分片划分都相同）。
    final gridStart = (start ~/ chunkSize) * chunkSize;
    return _fetch(gridStart, limitEnd, skip: start - gridStart);
  }

  Future<Uint8List> _fetch(int start, int end, {int skip = 0}) async {
    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        headers: {
          ...headers,
          'Range': 'bytes=$start-$end',
        },
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ),
      cancelToken: _cancelToken,
    );

    final body = response.data;
    if (body == null) {
      throw Exception('响应体为空');
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (!_running) break;
      builder.add(chunk);
    }

    var data = builder.takeBytes();
    final expected = end - start + 1;

    if (data.length < expected) {
      throw Exception('分片数据不完整: 期望 $expected, 实际 ${data.length}');
    }
    if (data.length > expected) {
      data = Uint8List.sublistView(data, 0, expected);
    }
    if (skip > 0) {
      if (skip >= data.length) {
        throw Exception('分片裁剪失败: start=$start skip=$skip');
      }
      return Uint8List.sublistView(data, skip);
    }
    return data;
  }

  // ================================================================
  // 背压控制
  // ================================================================

  /// 返回是否真的拿到了槽位；只有拿到槽位的一方才需要 _releaseSlot()
  Future<bool> _acquireSlot() async {
    if (_pendingCount < maxBufferedChunks) {
      _pendingCount++;
      return true;
    }
    final completer = Completer<void>();
    _waitingWorkers.add(completer);
    await completer.future;
    // 被唤醒时要重新校验：可能已经被 shutdown 了
    if (!_running || _failReason != null) return false;
    _pendingCount++;
    return true;
  }

  void _releaseSlot() {
    if (_pendingCount > 0) _pendingCount--;
    if (_waitingWorkers.isNotEmpty) {
      final next = _waitingWorkers.removeAt(0);
      if (!next.isCompleted) next.complete();
    }
  }

  Future<void> _waitIfPaused() async {
    while (_consumerPaused && _running && _failReason == null) {
      final completer = Completer<void>();
      _resumeCompleter = completer;
      await completer.future;
      if (identical(_resumeCompleter, completer)) {
        _resumeCompleter = null;
      }
    }
  }

  // ================================================================
  // 生命周期
  // ================================================================

  void _wakeAll() {
    for (final completer in _waitingWorkers) {
      if (!completer.isCompleted) completer.complete();
    }
    _waitingWorkers.clear();

    final resume = _resumeCompleter;
    _resumeCompleter = null;
    if (resume != null && !resume.isCompleted) resume.complete();

    final pump = _pumpSignal;
    _pumpSignal = null;
    if (pump != null && !pump.isCompleted) pump.complete();
  }

  void _shutdown(String reason) {
    if (!_running) return;
    _running = false;
    _failReason ??= reason;
    log('[Downloader] 关闭: $reason');

    _cancelStallTimer();

    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel(reason);
    }

    _wakeAll();

    try {
      if (!_controller.isClosed) {
        // unawaited：不要在 shutdown 路径上 await，避免调用方被挂住
        unawaited(_controller.close().catchError((Object _) {}));
      }
    } catch (_) {}

    _orderedBuffer.clear();
  }

  /// 公开的取消方法
  void cancel([String reason = 'cancelled']) {
    _shutdown(reason);
  }
}