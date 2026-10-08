package com.example.yuanying

import org.json.JSONObject
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class MainActivity : AudioServiceActivity(), MethodCallHandler {

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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ===== 1) 初始化 NodeJSManager =====
        nodeJSManager = NodeJSManager.getInstance(applicationContext)

        // ===== 2) 挂回调 → 转发到 eventSink =====
        nodeJSManager.onPortReceived = { port, type ->
            val json = JSONObject().apply {
                put("port", port)
                put("type", type)
            }.toString()
            eventSink?.success(json)
        }
        nodeJSManager.onNodeReady = {
            val json = JSONObject().apply {
                put("event", "ready")
            }.toString()
            eventSink?.success(json)
        }

        // ===== 3) MethodChannel =====
        nodeJSChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tvbox/nodejs"
        )
        nodeJSChannel?.setMethodCallHandler(this)

        // ===== 4) EventChannel =====
        nodeJSEventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tvbox/nodejs/events"
        )
        nodeJSEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events

                if (!::nodeJSManager.isInitialized) return

                if (nodeJSManager.managementPort > 0) {
                    val json = JSONObject().apply {
                        put("port", nodeJSManager.managementPort)
                        put("type", "management")
                    }.toString()
                    events?.success(json)
                }
                if (nodeJSManager.spiderPort > 0) {
                    val json = JSONObject().apply {
                        put("port", nodeJSManager.spiderPort)
                        put("type", "spider")
                    }.toString()
                    events?.success(json)
                }
                if (nodeJSManager.isNodeReady) {
                    val json = JSONObject().apply {
                        put("event", "ready")
                    }.toString()
                    events?.success(json)
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onDestroy() {
        if (::nodeJSManager.isInitialized) {
            nodeJSManager.stopNodeJS()
        }
        stopService(Intent(this, com.ryanheise.audioservice.AudioService::class.java))
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }

    // ===== MethodCallHandler =====
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startNodeJS" -> {
                nodeJSManager.startNodeJS { success -> result.success(success) }
            }
            "loadSourceFromURL" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("INVALID_ARGS", "Missing url", null)
                    return
                }
                nodeJSManager.loadSourceFromURL(url) { success, message ->
                    result.success(
                        mapOf(
                            "success" to success,
                            "message" to (message ?: "")
                        )
                    )
                }
            }
            "deleteSource" -> {
                nodeJSManager.deleteSource { success -> result.success(success) }
            }
            "getSourcePath" -> {
                result.success(nodeJSManager.getDocumentsSourcePath())
            }
            "getNativeServerPort" -> {
                result.success(nodeJSManager.nativeServerPort)
            }
            "getManagementPort" -> {
                result.success(nodeJSManager.managementPort)
            }
            "getSpiderPort" -> {
                result.success(nodeJSManager.spiderPort)
            }
            "isNodeReady" -> {
                result.success(nodeJSManager.isNodeReady)
            }
            "stopNodeJS" -> {
                nodeJSManager.stopNodeJS()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}