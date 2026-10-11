import AVFoundation

/// iOS 后台音频保活引擎
///
/// 通过 AVAudioSourceNode 实时生成全零 PCM 缓冲区，
/// 让 AVAudioSession 持续处于"正在播放音频"的状态，
/// 从而满足 iOS 后台音频模式的前提条件。
///
/// 使用独占模式（无 mixWithOthers），保证锁屏控制栏全程保持。
class SilenceKeeper {
    static let shared = SilenceKeeper()

    private let _engine = AVAudioEngine()
    private var _silenceNode: AVAudioSourceNode?
    private var _isRunning = false
    private var _autoStopWorkItem: DispatchWorkItem?

    /// 供外部（MethodChannel）查询真实运行状态
    var isRunning: Bool { _isRunning }

    private init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    /// 启动保活引擎（幂等）
    ///
    /// - Parameter timeout: 可选超时（秒）。传 nil 表示不超时，需手动 stop()。
    func start(timeout: TimeInterval? = nil) {
        guard !_isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // 独占模式：无 mixWithOthers，保持锁屏控制栏
            try session.setCategory(.playback, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[SilenceKeeper] AVAudioSession 配置失败: \(error)")
            return
        }

        let node = AVAudioSourceNode { _, _, _, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in ablPointer {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return noErr
        }

        _engine.attach(node)
        _engine.connect(node, to: _engine.mainMixerNode, format: nil)

        do {
            try _engine.start()
            _silenceNode = node
            _isRunning = true
            print("[SilenceKeeper] 保活引擎已启动 (timeout=\(timeout.map { "\($0)s" } ?? "无"))")

            if let timeout = timeout {
                _scheduleAutoStop(after: timeout)
            }
        } catch {
            print("[SilenceKeeper] 引擎启动失败: \(error)")
            _engine.detach(node)
        }
    }

    /// 停止保活引擎（幂等）
    func stop() {
        _autoStopWorkItem?.cancel()
        _autoStopWorkItem = nil

        guard _isRunning else { return }

        _engine.stop()
        if let node = _silenceNode {
            _engine.detach(node)
            _silenceNode = nil
        }
        _isRunning = false
        print("[SilenceKeeper] 保活引擎已停止")
    }

    private func _scheduleAutoStop(after seconds: TimeInterval) {
        _autoStopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self._isRunning {
                print("[SilenceKeeper] 兜底 Timer 触发，自动停止保活")
                self.stop()
            }
        }
        _autoStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .ended {
            if let node = _silenceNode {
                _engine.detach(node)
                _silenceNode = nil
            }
            _isRunning = false
            start()
        }
    }
}