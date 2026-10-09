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
        // 监听音频中断（来电、闹钟等），中断结束后自动恢复
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    /// 启动保活引擎
    /// 幂等：重复调用不会产生副作用
    func start() {
        guard !_isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // 使用 playback 类别 + mixWithOthers，避免打断用户正在播放的其他音频
            // 注意：mixWithOthers 在此处是必要的，它能确保保活引擎与主播放器共存
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[SilenceKeeper] AVAudioSession 配置失败: \(error)")
            return
        }

        // 创建静音源节点：每次渲染回调时，将缓冲区全部填零
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in ablPointer {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
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

    /// 停止保活引擎
    /// 注意：不调用 session.setActive(false)，避免影响主播放器的音频会话
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

    /// 音频中断处理：中断结束后重新启动引擎
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .ended {
            // 中断结束，重新启动保活
            _isRunning = false
            start()
        }
    }
}