package com.example.yuanying

import android.os.Environment
import android.provider.Settings
import android.net.Uri
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
    private var pyBridge: PythonPluginBridge? = null

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.yuanying/storage"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isExternalStorageManager" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }
                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val appIntent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        if (appIntent.resolveActivity(packageManager) != null) {
                            startActivity(appIntent)
                        } else {
                            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                        }
                    }
                    result.success(null)
                }
                "isPackageInstalled" -> {
                    val pkgName = call.argument<String>("packageName")
                    if (pkgName.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        try {
                            packageManager.getPackageInfo(pkgName, 0)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "getPackageVersion" -> {
                    val pkgName = call.argument<String>("packageName")
                    if (pkgName.isNullOrEmpty()) {
                        result.success(null)
                    } else {
                        try {
                            val info = packageManager.getPackageInfo(pkgName, 0)
                            result.success(info.versionName)
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                }
                "getApkPath" -> {
                    val pkgName = call.argument<String>("packageName")
                    if (pkgName.isNullOrEmpty()) {
                        result.success(null)
                    } else {
                        try {
                            val info = packageManager.getApplicationInfo(pkgName, 0)
                            result.success(info.sourceDir)
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                }
                "uninstallPackage" -> {
                    val pkgName = call.argument<String>("packageName")
                    if (pkgName.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        try {
                            // 优先 ACTION_UNINSTALL_PACKAGE：弹系统卸载确认框
                            // ACTION_DELETE 在 Android 11+ 部分 ROM（含 MuMu）会被静默处理
                            val uninstallIntent = Intent(Intent.ACTION_UNINSTALL_PACKAGE).apply {
                                data = Uri.parse("package:$pkgName")
                                putExtra(Intent.EXTRA_RETURN_RESULT, false)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            if (uninstallIntent.resolveActivity(packageManager) != null) {
                                startActivity(uninstallIntent)
                                result.success(true)
                            } else {
                                // 兜底：回退 ACTION_DELETE
                                val fallback = Intent(Intent.ACTION_DELETE).apply {
                                    data = Uri.parse("package:$pkgName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(fallback)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            android.util.Log.w("MainActivity", "uninstallPackage failed: $e")
                            result.success(false)
                        }
                    }
                }
                "openAppDetails" -> {
                    val pkgName = call.argument<String>("packageName")
                    if (pkgName.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            intent.data = Uri.parse("package:$pkgName")
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "openAllFilesAccessForApp" -> {
                    val pkgName = call.argument<String>("packageName")
                    if (pkgName.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                                intent.data = Uri.parse("package:$pkgName")
                                startActivity(intent)
                            } else {
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                intent.data = Uri.parse("package:$pkgName")
                                startActivity(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        val bridge = PythonPluginBridge(applicationContext)
        bridge.registerChannel(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.yuanying/pyplugin")
        )
        pyBridge = bridge

        // py 插件配置 channel（保活等非业务开关，与业务 channel 解耦）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.yuanying/pyplugin/config"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepAlive" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    bridge.setKeepAlive(enabled)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

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
        
        // ===== 5) 服务托管前台服务（沙盒/插件服务保活） =====
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.yuanying/service_host"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(this, ServiceHostService::class.java).apply {
                            @Suppress("UNCHECKED_CAST")
                            val pidsArg = call.argument<List<Int>>("pids")
                            putIntegerArrayListExtra(
                                ServiceHostService.EXTRA_PIDS,
                                if (pidsArg != null) ArrayList(pidsArg) else arrayListOf()
                            )
                            putExtra(
                                ServiceHostService.EXTRA_COUNT,
                                call.argument<Int>("count") ?: 0
                            )
                            call.argument<Int>("services")?.let {
                                putExtra(ServiceHostService.EXTRA_SERVICES, it)
                            }
                            call.argument<Int>("plugins")?.let {
                                putExtra(ServiceHostService.EXTRA_PLUGINS, it)
                            }
                            call.argument<String>("gw")?.let {
                                putExtra(ServiceHostService.EXTRA_GW, it)
                            }
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.w("MainActivity", "service_host start failed: $e")
                        result.success(false)
                    }
                }
                "stopAll" -> {
                    try {
                        startService(
                            Intent(this, ServiceHostService::class.java)
                                .setAction(ServiceHostService.ACTION_STOP_ALL)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.w("MainActivity", "service_host stopAll failed: $e")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::nodeJSManager.isInitialized) {
            nodeJSManager.stopNodeJS()
        }
        // 断开 py 插件绑定，避免 ServiceConnection 泄漏
        try {
            pyBridge?.unbind()
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "pyBridge.unbind failed: $e")
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