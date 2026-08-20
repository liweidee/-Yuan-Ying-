// ============================================================
// 文件：AppDelegate.swift
// 说明：在【原始附件 AppDelegate.swift】基础上，仅新增 1 个系统生命周期方法。
//       所有方法名/属性均来自你原文件（stopNodeJS/startNodeJS/spiderPort/eventSink 等），
//       未新增任何属性、未修改原有方法。
// ============================================================

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var nodeJSChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    fileprivate var eventSink: FlutterEventSink?
    fileprivate var managementPort: Int = 0
    fileprivate var spiderPort: Int = 0
    fileprivate var isNodeReady: Bool = false

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let flutterViewController = FlutterViewController()
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = flutterViewController
        window?.makeKeyAndVisible()

        GeneratedPluginRegistrant.register(with: self)

        setupNodeJSChannel(with: flutterViewController)
        setupEventChannel(with: flutterViewController)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNodePortNotification(_:)),
            name: NSNotification.Name("NodeServerPortReceived"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNodeReady(_:)),
            name: NSNotification.Name("NodeReady"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNodeMessage(_:)),
            name: NSNotification.Name("NodeMessageReceived"),
            object: nil
        )

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // [PATCH-A] 新增：前台恢复时静默探活 Node.js，死亡则重启（不通知 Flutter、不弹窗）
    // 位置：放在 didFinishLaunchingWithOptions 之后，setupNodeJSChannel 之前或之后均可。
    // 说明：仅当当前是 nodejs_ 源（由 Flutter 侧在切换站点时通过 UserDefaults 标记）才处理，
    //       非 nodejs_ 源完全不触发任何重启逻辑。探活用你原 handleNodePortNotification
    //       已同步到 spiderPort 的端口，请求 /config，1.5 秒超时即视为死亡。
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)

        // 仅 nodejs_ 源需要保活；标记由 Flutter 侧 nodejs_spider_service.dart 写入（见 PATCH-D）
        let isNode = UserDefaults.standard.bool(forKey: "is_current_nodejs_config")
        guard isNode else { return }

        // 若原生已知状态为未运行，直接重启
        if !NodeJSManager.shared().isRunning {
            NodeJSManager.shared().startNodeJS { _ in }
            return
        }

        // 轻量探活：请求 /config，超时或失败则静默重启
        guard spiderPort > 0,
              let url = URL(string: "http://127.0.0.1:\(spiderPort)/config") else { return }

        let task = URLSession.shared.dataTask(with: url) { _, resp, _ in
            if let r = resp as? HTTPURLResponse, r.statusCode == 200 {
                return // 服务正常，什么都不做
            }
            DispatchQueue.main.async {
                // 服务死亡：stop 清状态 + 重启，不传 completion、不弹窗
                NodeJSManager.shared().stopNodeJS()
                NodeJSManager.shared().startNodeJS { _ in }
            }
        }
        task.resume()
        // 1.5 秒后取消探活，避免阻塞
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { task.cancel() }
    }

    private func setupNodeJSChannel(with controller: FlutterViewController?) {
        guard let controller = controller else { return }

        nodeJSChannel = FlutterMethodChannel(
            name: "com.tvbox/nodejs",
            binaryMessenger: controller.binaryMessenger
        )

        nodeJSChannel?.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            switch call.method {
            case "startNodeJS":
                NodeJSManager.shared().startNodeJS { success in
                    result(success)
                }

            case "getNativeServerPort":
                result(NodeJSManager.shared().getNativeServerPort())

            case "getManagementPort":
                result(NodeJSManager.shared().getManagementPort())

            case "getSpiderPort":
                result(NodeJSManager.shared().getSpiderPort())

            case "isNodeReady":
                result(NodeJSManager.shared().isNodeReady)

            case "stopNodeJS":
                NodeJSManager.shared().stopNodeJS()
                result(nil)

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
                NodeJSManager.shared().deleteSource(completion: { success in
                    result(success)
                })

            case "getSourcePath":
                result(NodeJSManager.shared().getDocumentsSourcePath())

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func setupEventChannel(with controller: FlutterViewController?) {
        guard let controller = controller else { return }

        eventChannel = FlutterEventChannel(
            name: "com.tvbox/nodejs/events",
            binaryMessenger: controller.binaryMessenger
        )

        eventChannel?.setStreamHandler(NodeEventStreamHandler.shared)
        NodeEventStreamHandler.shared.setAppDelegate(self)
    }

    @objc private func handleNodePortNotification(_ notification: Notification) {
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

    @objc private func handleNodeReady(_ notification: Notification) {
        isNodeReady = true

        let eventData: [String: Any] = ["event": "ready"]
        if let jsonData = try? JSONSerialization.data(withJSONObject: eventData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            eventSink?(jsonString)
        }
    }

    @objc private func handleNodeMessage(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? String else { return }

        let eventData: [String: Any] = ["event": "message", "message": message]
        if let jsonData = try? JSONSerialization.data(withJSONObject: eventData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            eventSink?(jsonString)
        }
    }
}

class NodeEventStreamHandler: NSObject, FlutterStreamHandler {
    static let shared = NodeEventStreamHandler()
    private weak var appDelegate: AppDelegate?

    func setAppDelegate(_ delegate: AppDelegate) {
        self.appDelegate = delegate
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        appDelegate?.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        appDelegate?.eventSink = nil
        return nil
    }
}
