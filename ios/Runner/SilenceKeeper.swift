import AVFoundation

/// 保活模式
enum SilenceMode {
    /// 独占模式：无 mixWithOthers，用于音乐场景（保持控制栏）
    case exclusive
    /// 混合模式：有 mixWithOthers，用于 NodeJS 保活（不打扰其他 App）
    case mixable
}

/// iOS 后台音频保活引擎
class SilenceKeeper {
    static let shared = SilenceKeeper()

    private let _engine = AVAudioEngine()
    private var _silenceNode: AVAudioSourceNode?
    private var _isRunning = false
    private var _autoStopWorkItem: DispatchWorkItem?
    private var _currentMode: SilenceMode = .exclusive

    var isRunning: Bool { _isRunning }
    var currentMode: SilenceMode { _currentMode }

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
    /// - Parameters:
    ///   - mode: 独占或混合模式。默认独占。
    ///   - timeout: 可选超时（秒）。传 nil 表示不超时，需手动 stop()。
    func start(mode: SilenceMode = .exclusive, timeout: TimeInterval? = nil) {
        // 已在运行：如果模式一致，幂等返回；否则切换到新模式
        if _isRunning {
            if _currentMode == mode {
                return
            }
            _stopInternal()
        }
        _currentMode = mode

        let session = AVAudioSession.sharedInstance()
        do {
            let options: AVAudioSession.CategoryOptions =
                (mode == .mixable) ? [.mixWithOthers] : []
            try session.setCategory(.playback, options: options)
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
            let modeStr = (mode == .exclusive) ? "独占" : "混合"
            print("[SilenceKeeper] 保活引擎已启动 (模式=\(modeStr), timeout=\(timeout.map { "\($0)s" } ?? "无"))")

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
        _stopInternal()
        print("[SilenceKeeper] 保活引擎已停止")
    }

    private func _stopInternal() {
        _engine.stop()
        if let node = _silenceNode {
            _engine.detach(node)
            _silenceNode = nil
        }
        _isRunning = false
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
            let preservedMode = _currentMode
            _stopInternal()
            start(mode: preservedMode)
        }
    }
}