import Foundation

@objc class NodeJSBridge: NSObject {
    @objc static let shared = NodeJSBridge()

    private override init() {
        super.init()
    }

    @objc func startNodeJS(completion: @escaping (Bool) -> Void) {
        NodeJSManager.shared().startNodeJS { success in
            completion(success)
        }
    }

    @objc func stopNodeJS() {
        NodeJSManager.shared().stopNodeJS()
    }

    @objc func startKeepAlive() {
        SilenceKeeper.shared.start(timeout: nil)  // 无超时，长期保活
    }

    @objc func stopKeepAlive() {
        SilenceKeeper.shared.stop()
    }
}
