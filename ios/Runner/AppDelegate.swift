import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // ===== 存储 MethodChannel 引用 =====
  private var nodeJSChannel: FlutterMethodChannel?
  private var nodeJSEventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.applicationSupportsShakeToEdit = false
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ===== Flutter 3.41+ UIScene 迁移后的正确入口 =====
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    
    // ===== 用 applicationRegistrar.messenger() 替代旧的 controller.binaryMessenger =====
    let binaryMessenger = engineBridge.applicationRegistrar.messenger()
    
    // ===== 注册 Node.js MethodChannel =====
    let nodeJSChannel = FlutterMethodChannel(
      name: "com.tvbox/nodejs",
      binaryMessenger: binaryMessenger
    )
    self.nodeJSChannel = nodeJSChannel
    
    // ===== 注册 EventChannel =====
    let eventChannel = FlutterEventChannel(
      name: "com.tvbox/nodejs/events",
      binaryMessenger: binaryMessenger
    )
    self.nodeJSEventChannel = eventChannel
    eventChannel.setStreamHandler(self)
    
    // ===== 设置 MethodChannel 处理器 =====
    nodeJSChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
    
    // ===== 监听 Node.js 端口通知 =====
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onNodePortReceived(_:)),
      name: NSNotification.Name("NodeServerPortReceived"),
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onNodeReady(_:)),
      name: NSNotification.Name("NodeReady"),
      object: nil
    )
  }
  
  // ===== 处理 MethodChannel 调用 =====
  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startNodeJS":
      NodeJSManager.shared().startNodeJS { success in
        result(success)
      }
      
    case "loadSourceFromURL":
      guard let args = call.arguments as? [String: Any],
            let url = args["url"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing url", details: nil))
        return
      }
      // ===== 修复 2：OC 方法 loadSourceFromURL: 映射为 Swift 的 fromURL: =====
      NodeJSManager.shared().loadSource(fromURL: url) { success, message in
        if success {
          result(["success": true])
        } else {
          result(["success": false, "message": message ?? "Unknown error"])
        }
      }
      
    case "deleteSource":
      NodeJSManager.shared().deleteSource { success in
        result(success)
      }
      
    case "getSourcePath":
      let path = NodeJSManager.shared().getDocumentsSourcePath()
      result(path)
      
    case "stopNodeJS":
      NodeJSManager.shared().stopNodeJS()
      result(nil)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  // ===== 接收端口通知 =====
  @objc private func onNodePortReceived(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let port = userInfo["port"] as? Int,
          let type = userInfo["type"] as? String else { return }
    
    let data: [String: Any] = [
      "port": port,
      "type": type
    ]
    eventSink?(data)
  }
  
  // ===== 接收就绪通知 =====
  @objc private func onNodeReady(_ notification: Notification) {
    eventSink?(["event": "ready"])
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

// ===== EventChannel StreamHandler 实现 =====
extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}