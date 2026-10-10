import AVFoundation

/// iOS 后台音频保活引擎
///
/// 通过 AVAudioSourceNode 实时生成全零 PCM 缓冲区，
/// 让 AVAudioSession 持续处于"正在播放音频"的状态，
/// 从而满足 iOS 后台音频模式的前提条件。
class SilenceKeeper {
    static let shared = SilenceKeeper()

    private let _engine = AVAudioEngine()
    private var _silenceNode: AVAudioSourceNode?
    private var _isRunning = false

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
    func start() {
        guard !_isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // 只在当前 category 不是 .playback 时才设置，避免覆盖主播放器的音频会话配置
            // （主播放器由 audio_session 插件配置为 .playback，不能被改为 .ambient 等）
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
            print("[SilenceKeeper] 保活引擎已启动")
        } catch {
            print("[SilenceKeeper] 引擎启动失败: \(error)")
            _engine.detach(node)
        }
    }

    /// 停止保活引擎（幂等）
    ///
    /// 不调用 session.setActive(false)，避免影响主播放器仍在使用的音频会话。
    func stop() {
        guard _isRunning else { return }

        _engine.stop()
        if let node = _silenceNode {
            _engine.detach(node)
            _silenceNode = nil
        }
        _isRunning = false
        print("[SilenceKeeper] 保活引擎已停止")
    }

    /// 音频中断处理：中断结束后重新启动
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .ended {
            // 中断结束，重置标志并重新启动
            if let node = _silenceNode {
                _engine.detach(node)
                _silenceNode = nil
            }
            _isRunning = false
            start()
        }
    }
}