import AVFoundation
import AVKit
import Flutter
import UIKit

final class IosPipManager: NSObject, AVPictureInPictureControllerDelegate {
  static let shared = IosPipManager()

  private var channel: FlutterMethodChannel?
  private var pipController: AVPictureInPictureController?
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var containerView: UIView?
  private var itemStatusObservation: NSKeyValueObservation?
  private var possibleObservation: NSKeyValueObservation?
  private var readyForDisplayObservation: NSKeyValueObservation?
  private var replaceStatusObservation: NSKeyValueObservation?
  private var itemEndObserver: NSObjectProtocol?
  private var timeoutWorkItem: DispatchWorkItem?
  private var retryTimer: Timer?
  private var sessionId: UInt64 = 0
  private var currentEpisodeIndex = 0

  private override init() {
    super.init()
  }

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pictureInPictureStatus":
      result([
        "supported": AVPictureInPictureController.isPictureInPictureSupported(),
        "active": pipController?.isPictureInPictureActive ?? false,
      ])

    case "enterPictureInPicture":
      ensureAudioSession()
      guard AVPictureInPictureController.isPictureInPictureSupported() else {
        result([
          "supported": false,
          "active": false,
          "requested": false,
          "error": "当前设备或系统未支持画中画功能",
        ])
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let urlText = arguments["url"] as? String,
            let url = parseMediaUrl(urlText) else {
        result([
          "supported": true,
          "active": false,
          "requested": false,
          "error": "未找到可用的画中画视频地址",
        ])
        return
      }
      let headers = arguments["headers"] as? [String: String] ?? [:]
      let positionMs = (arguments["position"] as? NSNumber)?.intValue ?? 0
      let speed = (arguments["speed"] as? NSNumber)?.floatValue ?? 1.0
      let episodeIndex = (arguments["episodeIndex"] as? NSNumber)?.intValue ?? 0
      let sourceRect = parseSourceRect(arguments)
      startPip(
        url: url,
        headers: headers,
        positionMs: positionMs,
        speed: speed,
        episodeIndex: episodeIndex,
        sourceRect: sourceRect,
        result: result
      )

    case "replacePictureInPictureItem":
      guard let arguments = call.arguments as? [String: Any],
            let urlText = arguments["url"] as? String,
            let url = parseMediaUrl(urlText) else {
        result(["replaced": false, "error": "视频地址解析失败"])
        return
      }
      let headers = arguments["headers"] as? [String: String] ?? [:]
      let episodeIndex =
        (arguments["episodeIndex"] as? NSNumber)?.intValue ?? currentEpisodeIndex
      let speed = (arguments["speed"] as? NSNumber)?.floatValue ?? 1.0
      replaceItem(
        url: url,
        headers: headers,
        episodeIndex: episodeIndex,
        speed: speed,
        result: result
      )

    case "stopPictureInPicture":
      let position = currentPositionMs()
      if let controller = pipController, controller.isPictureInPictureActive {
        controller.stopPictureInPicture()
      } else {
        cleanUpPip()
        notifyChanged(active: false, position: position)
      }
      result(["stopped": true, "position": position])

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startPip(
    url: URL,
    headers: [String: String],
    positionMs: Int,
    speed: Float,
    episodeIndex: Int,
    sourceRect: CGRect?,
    result: @escaping FlutterResult
  ) {
    ensureAudioSession()
    cleanUpPip()
    let activeSessionId = sessionId

    let assetOptions = assetOptions(for: url, headers: headers)
    let item = AVPlayerItem(asset: AVURLAsset(url: url, options: assetOptions))
    let player = AVPlayer(playerItem: item)
    player.actionAtItemEnd = .none
    if #available(iOS 16.0, *) {
      player.preventsDisplaySleepDuringVideoPlayback = true
    }
    self.player = player
    currentEpisodeIndex = episodeIndex
    observeItemEnd(item, sessionId: activeSessionId)

    guard let root = activeRootViewController else {
      cleanUpPip()
      result([
        "supported": true,
        "active": false,
        "requested": false,
        "error": "无法获取应用窗口视图，请在界面显示后重试",
      ])
      return
    }

    let view = UIView(frame: sourceRect ?? root.view.bounds)
    view.backgroundColor = .black
    view.alpha = 0
    view.isUserInteractionEnabled = false
    root.view.addSubview(view)
    containerView = view

    let layer = AVPlayerLayer(player: player)
    layer.frame = view.bounds
    layer.videoGravity = .resizeAspect
    view.layer.addSublayer(layer)
    playerLayer = layer

    guard let controller = AVPictureInPictureController(playerLayer: layer) else {
      cleanUpPip()
      result([
        "supported": true,
        "active": false,
        "requested": false,
        "error": "无法创建系统画中画控制器",
      ])
      return
    }
    controller.delegate = self
    if #available(iOS 14.2, *) {
      controller.canStartPictureInPictureAutomaticallyFromInline = true
    }
    pipController = controller

    var started = false
    let attemptStart = { [weak self] in
      guard let self = self,
            self.sessionId == activeSessionId,
            !started,
            let controller = self.pipController else { return }
      guard controller.isPictureInPicturePossible,
            self.playerLayer?.isReadyForDisplay == true else { return }
      started = true
      self.stopStartObservers()
      self.containerView?.alpha = 1.0
      self.ensureAudioSession()
      controller.startPictureInPicture()
    }

    itemStatusObservation = item.observe(\.status, options: [.new, .initial]) {
      [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self, self.sessionId == activeSessionId else { return }
        guard item.status == .readyToPlay else {
          if item.status == .failed {
            let message = item.error?.localizedDescription ?? "视频加载异常"
            self.cleanUpPip()
            self.notifyChanged(
              active: false,
              error: "当前视频无法在画中画中播放: \(message)"
            )
          }
          return
        }
        self.itemStatusObservation?.invalidate()
        self.itemStatusObservation = nil

        var hasStartedPlayback = false
        let beginPlayback = {
          guard self.sessionId == activeSessionId, !hasStartedPlayback else {
            return
          }
          hasStartedPlayback = true
          self.player?.playImmediately(atRate: speed)
          self.readyForDisplayObservation =
            self.playerLayer?.observe(\.isReadyForDisplay, options: [.new, .initial]) {
              _, _ in
              DispatchQueue.main.async { attemptStart() }
            }
          self.possibleObservation = self.pipController?.observe(
            \.isPictureInPicturePossible,
            options: [.new, .initial]
          ) { _, _ in
            DispatchQueue.main.async { attemptStart() }
          }
          self.retryTimer?.invalidate()
          self.retryTimer = Timer.scheduledTimer(
            withTimeInterval: 0.2,
            repeats: true
          ) { [weak self] timer in
            guard let self = self, self.sessionId == activeSessionId else {
              timer.invalidate()
              return
            }
            if started || (self.pipController?.isPictureInPictureActive ?? false) {
              timer.invalidate()
            } else {
              attemptStart()
            }
          }
        }

        if positionMs > 0 {
          let time = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            beginPlayback()
          }
          player.seek(
            to: time,
            toleranceBefore: CMTime(value: 500, timescale: 1000),
            toleranceAfter: CMTime(value: 500, timescale: 1000)
          ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              beginPlayback()
            }
          }
        } else {
          beginPlayback()
        }
      }
    }

    let timeout = DispatchWorkItem { [weak self] in
      guard let self = self, self.sessionId == activeSessionId else { return }
      guard !(self.pipController?.isPictureInPictureActive ?? false) else {
        return
      }
      self.cleanUpPip()
      self.notifyChanged(
        active: false,
        error: "启动画中画未就绪，请检查网络或系统画中画设置"
      )
    }
    timeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: timeout)

    result(["supported": true, "active": false, "requested": true])
  }

  private func replaceItem(
    url: URL,
    headers: [String: String],
    episodeIndex: Int,
    speed: Float,
    result: @escaping FlutterResult
  ) {
    guard let player = player,
          pipController?.isPictureInPictureActive == true else {
      result(["replaced": false, "error": "画中画已关闭"])
      return
    }
    let activeSessionId = sessionId
    let assetOptions = assetOptions(for: url, headers: headers)
    let item = AVPlayerItem(asset: AVURLAsset(url: url, options: assetOptions))
    replaceStatusObservation?.invalidate()
    replaceStatusObservation = item.observe(\.status, options: [.new]) {
      [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self, self.sessionId == activeSessionId else { return }
        if item.status == .readyToPlay {
          self.replaceStatusObservation?.invalidate()
          self.replaceStatusObservation = nil
          self.player?.playImmediately(atRate: speed)
        } else if item.status == .failed {
          self.replaceStatusObservation?.invalidate()
          self.replaceStatusObservation = nil
          self.channel?.invokeMethod(
            "iosPipItemFailed",
            arguments: [
              "episodeIndex": episodeIndex,
              "error": item.error?.localizedDescription ?? "视频加载异常",
            ]
          )
        }
      }
    }
    currentEpisodeIndex = episodeIndex
    observeItemEnd(item, sessionId: activeSessionId)
    player.replaceCurrentItem(with: item)
    player.playImmediately(atRate: speed)
    result(["replaced": true])
  }

  private func observeItemEnd(_ item: AVPlayerItem, sessionId: UInt64) {
    if let observer = itemEndObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    itemEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self = self,
            self.sessionId == sessionId,
            self.pipController?.isPictureInPictureActive == true else {
        return
      }
      self.channel?.invokeMethod(
        "iosPipItemEnded",
        arguments: ["episodeIndex": self.currentEpisodeIndex]
      )
    }
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    guard pictureInPictureController === pipController else { return }
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    stopStartObservers()
    containerView?.isHidden = true
    notifyChanged(active: true, position: currentPositionMs())
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
    completionHandler: @escaping (Bool) -> Void
  ) {
    guard pictureInPictureController === pipController else {
      completionHandler(false)
      return
    }
    let position = currentPositionMs()
    var completed = false
    let finish: (Bool) -> Void = { value in
      guard !completed else { return }
      completed = true
      completionHandler(value)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
      finish(true)
    }
    guard let channel = channel else {
      finish(true)
      return
    }
    channel.invokeMethod(
      "iosPipRestoreUI",
      arguments: [
        "position": position,
        "episodeIndex": currentEpisodeIndex,
      ]
    ) { _ in
      finish(true)
    }
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    guard pictureInPictureController === pipController else { return }
    let position = currentPositionMs()
    notifyChanged(active: false, position: position)
    cleanUpPip()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    guard pictureInPictureController === pipController else { return }
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    cleanUpPip()
    notifyChanged(active: false, error: error.localizedDescription)
  }

  private func stopStartObservers() {
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    retryTimer?.invalidate()
    retryTimer = nil
    possibleObservation?.invalidate()
    possibleObservation = nil
    readyForDisplayObservation?.invalidate()
    readyForDisplayObservation = nil
    itemStatusObservation?.invalidate()
    itemStatusObservation = nil
  }

  private func cleanUpPip() {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in self?.cleanUpPip() }
      return
    }
    sessionId &+= 1
    stopStartObservers()
    replaceStatusObservation?.invalidate()
    replaceStatusObservation = nil
    if let observer = itemEndObserver {
      NotificationCenter.default.removeObserver(observer)
      itemEndObserver = nil
    }
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    containerView?.removeFromSuperview()
    containerView = nil
    pipController?.delegate = nil
    pipController = nil
  }

  private func notifyChanged(
    active: Bool,
    position: Int? = nil,
    error: String? = nil
  ) {
    var arguments: [String: Any] = [
      "active": active,
      "supported": AVPictureInPictureController.isPictureInPictureSupported(),
      "episodeIndex": currentEpisodeIndex,
    ]
    if let position = position {
      arguments["position"] = position
    }
    if let error = error {
      arguments["error"] = error
    }
    channel?.invokeMethod("iosPipChanged", arguments: arguments)
  }

  private func assetOptions(
    for url: URL,
    headers: [String: String]
  ) -> [String: Any] {
    guard !url.isFileURL, !headers.isEmpty else { return [:] }
    return ["AVURLAssetHTTPHeaderFieldsKey": headers]
  }

  private func parseMediaUrl(_ raw: String) -> URL? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    if value.hasPrefix("file://") {
      return URL(fileURLWithPath: String(value.dropFirst(7)))
    }
    if value.hasPrefix("/") {
      return URL(fileURLWithPath: value)
    }
    if let url = URL(string: value) {
      return url
    }
    if let encoded = value.addingPercentEncoding(
      withAllowedCharacters: .urlQueryAllowed
    ) {
      return URL(string: encoded)
    }
    return nil
  }

  private func parseSourceRect(_ arguments: [String: Any]) -> CGRect? {
    let scale = UIScreen.main.scale > 0 ? UIScreen.main.scale : 1
    if let x = (arguments["x"] as? NSNumber)?.doubleValue,
       let y = (arguments["y"] as? NSNumber)?.doubleValue,
       let width = (arguments["width"] as? NSNumber)?.doubleValue,
       let height = (arguments["height"] as? NSNumber)?.doubleValue,
       width > 0, height > 0 {
      return CGRect(
        x: x / scale,
        y: y / scale,
        width: width / scale,
        height: height / scale
      )
    }
    if let left = (arguments["left"] as? NSNumber)?.doubleValue,
       let top = (arguments["top"] as? NSNumber)?.doubleValue,
       let right = (arguments["right"] as? NSNumber)?.doubleValue,
       let bottom = (arguments["bottom"] as? NSNumber)?.doubleValue,
       right > left, bottom > top {
      return CGRect(
        x: left / scale,
        y: top / scale,
        width: (right - left) / scale,
        height: (bottom - top) / scale
      )
    }
    return nil
  }

  private func currentPositionMs() -> Int {
    guard let seconds = player?.currentTime().seconds,
          seconds.isFinite,
          seconds >= 0 else {
      return 0
    }
    return Int(min(seconds * 1000.0, Double(Int.max)))
  }

  private func ensureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback)
      try session.setActive(true)
    } catch {
      NSLog("[iOS PiP] audio session error: %@", error.localizedDescription)
    }
  }

  private var activeRootViewController: UIViewController? {
    if let appDelegate = UIApplication.shared.delegate,
       let window = appDelegate.window ?? nil,
       let root = window.rootViewController {
      return root
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let root = window.rootViewController {
          return root
        }
      }
    }
    return nil
  }
}
