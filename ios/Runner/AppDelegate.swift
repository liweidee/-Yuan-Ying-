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
