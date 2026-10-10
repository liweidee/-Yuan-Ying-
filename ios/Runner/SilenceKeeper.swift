import AVFoundation

/// iOS 后台音频保活引擎
///
/// 通过 AVAudioSourceNode 实时生成全零 PCM 缓冲区，
/// 让 AVAudioSession 持续处于"正在播放音频"的状态，
/// 从而满足 iOS 后台音频模式的前提条件。
///
/// 使用方式：
/// - 短时保活（切歌窗口）：`start(timeout: 30)`，30 秒后自动停止
/// - 长期保活（后台服务）：`start()`，需手动调用 `stop()`
class SilenceKeeper {
    static let shared = SilenceKeeper()

    private let _engine = AVAudioEngine()
    private var _silenceNode: AVAudioSourceNode?
    private var _isRunning = false
    private var _autoStopWorkItem: DispatchWorkItem?

    /// 供外部（MethodChannel）查询真实运行状态
    var isRunning: Bool { _isRunning }

    private init() {
        // 使用闭包式监听，避免继承 NSObject 才能用 #selector 的限制
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
    ///                      用于兜底：防止调用方异常未调用 stop() 导致引擎长期泄漏。
    func start(timeout: TimeInterval? = nil) {
        guard !_isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // 只在当前 category 不是 .playback 时才设置，避免覆盖主播放器的音频会话配置
            if session.category != .playback {
                try session.setCategory(.playback, options: [])
            }
            try session.setActive(true)
        } catch {
            print("[SilenceKeeper] AVAudioSession 配置失败: \(error)")
            return
        }

        // 静音源节点：每次渲染回调时，把缓冲区全部填零
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

            // 仅在明确传入 timeout 时才调度自动停止
            if let timeout = timeout {
                _scheduleAutoStop(after: timeout)
            }
        } catch {
            print("[SilenceKeeper] 引擎启动失败: \(error)")
            _engine.detach(node)
        }
    }

    /// 停止保活引擎（幂等）
    ///
    /// 不调用 session.setActive(false)，避免影响主播放器仍在使用的音频会话。
    func stop() {
        // 取消兜底 Timer
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

    /// 调度兜底自动停止
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

    /// 音频中断处理：中断结束后重新启动
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .ended {
            // 中断结束，重置标志并重新启动（不超时，由调用方后续处理）
            if let node = _silenceNode {
                _engine.detach(node)
                _silenceNode = nil
            }
            _isRunning = false
            start()  // 中断恢复时不带 timeout，避免恢复后再被计时停掉
        }
    }
}