package com.example.yuanying

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Environment
import android.provider.Settings
import android.net.Uri
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import com.dsplayer.ds_player.jar_spider.JarSpiderHost
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

class MainActivity : AudioServiceActivity() {

    private var pyBridge: PythonPluginBridge? = null
    private var pipChannel: MethodChannel? = null
    private var pendingStoragePermissionResult: Result? = null

    companion object {
        private const val RECORDING_STORAGE_PERMISSION_REQUEST = 4201
    }

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
                    openAllFilesAccessSettings()
                    result.success(null)
                }
                "hasRecordingStorageAccess" -> {
                    result.success(hasRecordingStorageAccess())
                }
                "requestRecordingStorageAccess" -> {
                    if (hasRecordingStorageAccess()) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        openAllFilesAccessSettings()
                        result.success(false)
                    } else {
                        pendingStoragePermissionResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                            RECORDING_STORAGE_PERMISSION_REQUEST
                        )
                    }
                }
                "getRecordingDirectory" -> {
                    if (!hasRecordingStorageAccess()) {
                        result.success(null)
                    } else {
                        val movies = Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_MOVIES
                        )
                        val directory = File(movies, "源影录制")
                        if (!directory.exists() && !directory.mkdirs()) {
                            result.success(null)
                        } else {
                            result.success(directory.absolutePath)
                        }
                    }
                }
                "scanRecordingFile" -> {
                    val filePath = call.argument<String>("path")
                    if (filePath.isNullOrBlank() || !File(filePath).exists()) {
                        result.success(false)
                    } else {
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(filePath),
                            arrayOf("video/mp4")
                        ) { _, uri ->
                            runOnUiThread { result.success(uri != null) }
                        }
                    }
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

        JarSpiderHost.register(this, flutterEngine.dartExecutor.binaryMessenger)

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

        // Android Node 运行时改由插件提供，原生侧仅同步 assets 项目资源。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.yuanying/node_assets"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareProject" -> {
                    try {
                        result.success(NodeAssetsManager.prepareProject(applicationContext))
                    } catch (e: Exception) {
                        result.error("NODE_ASSETS_FAILED", e.message ?: "unknown error", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // ===== 服务托管前台服务（沙盒/插件与猫影视 Node 保活） =====
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.yuanying/service_host"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(this, ServiceHostService::class.java).apply {
                            action = ServiceHostService.ACTION_UPDATE_SANDBOX
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
                        val hasPids = (call.argument<List<Int>>("pids") ?: emptyList()).isNotEmpty()
                        startHostService(intent, requireForeground = hasPids)
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.w("MainActivity", "service_host start failed: $e")
                        result.success(false)
                    }
                }
                "syncCatVod" -> {
                    try {
                        val active = call.argument<Boolean>("active") ?: false
                        val pid = call.argument<Int>("pid")
                        val intent = Intent(this, ServiceHostService::class.java).apply {
                            action = ServiceHostService.ACTION_UPDATE_CATVOD
                            putExtra(ServiceHostService.EXTRA_CATVOD_ACTIVE, active)
                            putExtra(
                                ServiceHostService.EXTRA_CATVOD_PID,
                                if (active && pid != null && pid > 0) pid else 0
                            )
                        }
                        startHostService(intent, requireForeground = active)
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.w("MainActivity", "service_host syncCatVod failed: $e")
                        result.success(false)
                    }
                }
                "consumeCatVodStopRequest" -> {
                    val prefs = getSharedPreferences(
                        ServiceHostService.PREFS_NAME,
                        MODE_PRIVATE
                    )
                    val requested = prefs.getBoolean(
                        ServiceHostService.PREF_CATVOD_STOP_REQUESTED,
                        false
                    )
                    if (requested) {
                        prefs.edit()
                            .remove(ServiceHostService.PREF_CATVOD_STOP_REQUESTED)
                            .apply()
                    }
                    result.success(requested)
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

        // ===== 6) Android 画中画 (PiP) =====
        // 保存到字段 pipChannel，供 onPictureInPictureModeChanged 回传状态时复用。
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.yuanying/pip"
        )
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> {
                    // PiP 需要 Android 8.0 (API 26) 及以上
                    val available = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(available)
                }
                "enter" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            // 从 Flutter 接收宽高比，默认 16:9
                            val width = call.argument<Int>("width") ?: 16
                            val height = call.argument<Int>("height") ?: 9
                            val aspectRatio = android.util.Rational(width, height)
                            val params = android.app.PictureInPictureParams.Builder()
                                .setAspectRatio(aspectRatio)
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.w("MainActivity", "enter PiP failed: $e")
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startHostService(intent: Intent, requireForeground: Boolean) {
        if (requireForeground && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun hasRecordingStorageAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            true
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun openAllFilesAccessSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val appIntent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.parse("package:$packageName")
        }
        if (appIntent.resolveActivity(packageManager) != null) {
            startActivity(appIntent)
        } else {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != RECORDING_STORAGE_PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingStoragePermissionResult?.success(granted)
        pendingStoragePermissionResult = null
    }

    override fun onDestroy() {
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

        // 通知 Flutter 层 PiP 状态发生变化
        try {
            pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "notify PiP state failed: $e")
        }
    }

}
