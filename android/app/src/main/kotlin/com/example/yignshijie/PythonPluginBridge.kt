package com.example.yuanying

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import com.dsplayer.plugin.python.IPySpiderService
import io.flutter.plugin.common.MethodChannel
import java.io.File

class PythonPluginBridge(private val context: Context) {
    companion object {
        private const val TAG = "PythonBridge"
        private const val PKG = "com.dsplayer.plugin.python"
        private const val ACTION = "com.dsplayer.plugin.python.BIND_PY_SPIDER"
        private const val CHANNEL = "com.example.yuanying/pyplugin"
    }

    private var service: IPySpiderService? = null
    private var bound = false
    private val pending = mutableListOf<(IPySpiderService?) -> Unit>()

    /** 保活开关：true 时 bindService 使用 BIND_IMPORTANT，提升进程优先级 */
    @Volatile
    private var keepAlive = false

    private val conn = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = IPySpiderService.Stub.asInterface(binder)
            bound = true
            pending.forEach { it(service) }
            pending.clear()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            bound = false
        }
    }

    fun wake() {
        try {
            val intent = Intent().apply {
                component = ComponentName(PKG, "$PKG.WakeActivity")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "wake failed: $e")
        }
    }

    private fun bind(callback: (IPySpiderService?) -> Unit) {
        if (service != null) {
            callback(service)
            return
        }
        pending.add(callback)
        if (!bound) {
            try {
                val flags = Context.BIND_AUTO_CREATE or
                        (if (keepAlive) Context.BIND_IMPORTANT else 0)
                Log.i(TAG, "bindService flags=0x${Integer.toHexString(flags)} keepAlive=$keepAlive")
                bound = context.bindService(
                    Intent(ACTION).setPackage(PKG), conn, flags
                )
            } catch (e: Exception) {
                Log.w(TAG, "bind failed: $e")
                pending.remove(callback)
                callback(null)
            }
        }
    }

    /**
     * 设置保活开关。
     *
     * BIND_IMPORTANT 只在 bindService 调用时生效，对已 bound 的连接无法动态升级，
     * 所以切换后主动 unbind，下次请求进来时按新的 flags 重新 bind。
     *
     * 不清空 pending：pending 里的回调会在下次 bind 成功后执行
     * （与原代码 onServiceDisconnected 的行为保持一致，旧调用可能因超时已过期，
     *  但迟到的回调不会引发新问题）。
     */
    fun setKeepAlive(enabled: Boolean) {
        if (keepAlive == enabled) return
        keepAlive = enabled
        Log.i(TAG, "setKeepAlive -> $enabled, bound=$bound")
        if (bound) {
            try {
                context.unbindService(conn)
            } catch (e: Exception) {
                Log.w(TAG, "unbindService failed: $e")
            }
            bound = false
            service = null
        }
    }

    fun unbind() {
        if (bound) {
            try { context.unbindService(conn) } catch (_: Exception) {}
            bound = false
            service = null
        }
    }

    fun registerChannel(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> withService(result) { it.ping() }

                "loadSource" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "source"
                    if (bytes == null) {
                        result.error("INVALID", "bytes required", null)
                        return@setMethodCallHandler
                    }
                    val tmp = File(context.cacheDir, "py_src_${System.currentTimeMillis()}.tmp")
                    tmp.writeBytes(bytes)
                    val pfd = ParcelFileDescriptor.open(tmp, ParcelFileDescriptor.MODE_READ_ONLY)
                    wake()
                    bind { svc ->
                        if (svc == null) {
                            try { pfd.close() } catch (_: Exception) {}
                            result.error("NO_SERVICE", "PySpiderService not bound", null)
                            return@bind
                        }
                        try {
                            result.success(svc.loadSource(pfd, name))
                        } catch (e: Exception) {
                            result.error("CALL_FAILED", e.message, null)
                        } finally {
                            try { pfd.close() } catch (_: Exception) {}
                        }
                    }
                }

                "call" -> {
                    val key = call.argument<String>("key")
                    val method = call.argument<String>("method")
                    val env = call.argument<String>("env") ?: "{}"
                    val args = call.argument<String>("args") ?: "[]"
                    if (key == null || method == null) {
                        result.error("INVALID", "key/method required", null)
                        return@setMethodCallHandler
                    }
                    withService(result) { it.call(key, method, env, args) }
                }

                "unloadSource" -> {
                    val key = call.argument<String>("key")
                    if (key == null) {
                        result.error("INVALID", "key required", null)
                        return@setMethodCallHandler
                    }
                    withService(result) { it.unloadSource(key) }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun withService(result: MethodChannel.Result, block: (IPySpiderService) -> String) {
        wake()
        bind { svc ->
            if (svc == null) {
                result.error("NO_SERVICE", "PySpiderService not bound", null)
                return@bind
            }
            try {
                result.success(block(svc))
            } catch (e: Exception) {
                result.error("CALL_FAILED", e.message, null)
            }
        }
    }
}