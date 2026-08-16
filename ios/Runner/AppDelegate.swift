import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {

    // ===== Node.js 相关属性（与 tvbox_flutter 一致） =====
    private var nodeJSChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private var managementPort: Int = 0
    private var spiderPort: Int = 0
    private var isNodeReady: Bool = false

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        application.applicationSupportsShakeToEdit = false
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ===== FlutterImplicitEngineDelegate（你的项目原有，保留） =====
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        // 1. 注册所有插件（原有）
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        // 2. 获取二进制消息通道（用于 Flutter ↔ Native 通信）
        let binaryMessenger = engineBridge.applicationRegistrar.messenger()

        // 3. 注册 Node.js MethodChannel
        let nodeJSChannel = FlutterMethodChannel(
            name: "com.tvbox/nodejs",
            binaryMessenger: binaryMessenger
        )
        self.nodeJSChannel = nodeJSChannel
        nodeJSChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }

        // 4. 注册 Node.js EventChannel（用于 Native → Flutter 事件推送）
        let eventChannel = FlutterEventChannel(
            name: "com.tvbox/nodejs/events",
            binaryMessenger: binaryMessenger
        )
        self.eventChannel = eventChannel
        eventChannel.setStreamHandler(self)

        // 5. 监听 Node.js 进程上报的端口通知
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onNodeMessage(_:)),
            name: NSNotification.Name("NodeMessageReceived"),
            object: nil
        )
    }

    // ===== MethodChannel 处理器（完全移植 tvbox_flutter） =====
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startNodeJS":
            NodeJSManager.shared().startNodeJS { success in
                result(success)
            }

        case "loadSourceFromURL":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "url is required", details: nil))
                return
            }
            NodeJSManager.shared().loadSource(fromURL: url) { success, message in
                if success {
                    result(["success": true, "message": message ?? ""])
                } else {
                    result(FlutterError(code: "LOAD_FAILED", message: message ?? "Unknown error", details: nil))
                }
            }

        case "deleteSource":
            NodeJSManager.shared().deleteSource { success in
                result(success)
            }

        case "getSourcePath":
            result(NodeJSManager.shared().getDocumentsSourcePath())

        case "stopNodeJS":
            NodeJSManager.shared().stopNodeJS()
            result(nil)

        // 可选：如需支持以下方法，可取消注释（tvbox_flutter 中都有）
        // case "getNativeServerPort":
        //     result(NodeJSManager.shared().getNativeServerPort())
        // case "getManagementPort":
        //     result(NodeJSManager.shared().getManagementPort())
        // case "getSpiderPort":
        //     result(NodeJSManager.shared().getSpiderPort())
        // case "isNodeReady":
        //     result(NodeJSManager.shared().isNodeReady)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ===== 通知处理方法（完全移植 tvbox_flutter） =====
    @objc private func onNodePortReceived(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let port = userInfo["port"] as? Int,
              let type = userInfo["type"] as? String else { return }

        if type == "management" {
            managementPort = port
        } else if type == "spider" {
            spiderPort = port
        }

        let eventData: [String: Any] = ["port": port, "type": type]
        if let jsonData = try? JSONSerialization.data(withJSONObject: eventData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            eventSink?(jsonString)
        }
    }

    @objc private func onNodeReady(_ notification: Notification) {
        isNodeReady = true
        eventSink?(["event": "ready"])
    }

    @objc private func onNodeMessage(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? String else { return }
        eventSink?(["event": "message", "message": message])
    }

    // ===== FlutterStreamHandler 实现（用于 EventChannel） =====
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}