package com.example.yuanying

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class MainActivity : AudioServiceActivity(), MethodCallHandler {

    // ===== Node.js 通道 =====
    private var nodeJSChannel: MethodChannel? = null
    private var nodeJSEventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var nodeJSManager: NodeJSManager

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        // ===== 初始化 NodeJSManager =====
        nodeJSManager = NodeJSManager.getInstance(this)
        nodeJSManager.onPortReceived = { port, type ->
            eventSink?.success(mapOf("port" to port, "type" to type))
        }
        nodeJSManager.onNodeReady = {
            eventSink?.success(mapOf("event" to "ready"))
        }
    }

    // ===== 注册 Flutter 通道 =====
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nodeJSChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tvbox/nodejs"
        )
        nodeJSChannel?.setMethodCallHandler(this)

        nodeJSEventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tvbox/nodejs/events"
        )
        nodeJSEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onDestroy() {
        // ===== 停止 Node.js =====
        nodeJSManager.stopNodeJS()
        stopService(Intent(this, com.ryanheise.audioservice.AudioService::class.java))
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }

    // ===== MethodCallHandler 实现 =====
    override fun onMethodCall(call: MethodChannel.MethodCall, result: Result) {
        when (call.method) {
            "startNodeJS" -> {
                nodeJSManager.startNodeJS { success ->
                    result.success(success)
                }
            }

            "loadSourceFromURL" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("INVALID_ARGS", "Missing url", null)
                    return
                }
                nodeJSManager.loadSourceFromURL(url) { success, message ->
                    if (success) {
                        result.success(mapOf("success" to true))
                    } else {
                        result.success(mapOf("success" to false, "message" to (message ?: "Unknown error")))
                    }
                }
            }

            "deleteSource" -> {
                nodeJSManager.deleteSource { success ->
                    result.success(success)
                }
            }

            "getSourcePath" -> {
                result.success(nodeJSManager.getDocumentsSourcePath())
            }

            "stopNodeJS" -> {
                nodeJSManager.stopNodeJS()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}