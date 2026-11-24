package com.dsplayer.ds_player.jar_spider

import android.app.Activity
import android.os.Handler
import android.os.Looper
import dalvik.system.DexClassLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.regex.Pattern

/**
 * Android host for the official DsPlayer JAR plugin.
 *
 * Only the import mode is supported here. The official plugins/jar/classes.dex
 * is loaded from the Yuanying application-private plugin directory.
 */
object JarSpiderHost {
    private const val BRIDGE_CLASS = "com.dsplayer.plugin.jar.JarSpiderBridge"
    private const val CHANNEL = "com.dsplayer/jar_spider"
    private const val DEX_PATTERN = "classes\\d*\\.dex"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pool = Executors.newCachedThreadPool()
    private val dexPattern = Pattern.compile(DEX_PATTERN)

    private var bridge: IJarSpiderBridge? = null
    private var bridgeKey: String? = null
    private var channel: MethodChannel? = null

    fun register(activity: Activity, messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                pool.execute {
                    try {
                        val value = handle(activity, call)
                        mainHandler.post { result.success(value) }
                    } catch (error: Throwable) {
                        android.util.Log.e(
                            "JarSpider",
                            "JAR bridge channel failed: ${call.method}",
                            error,
                        )
                        mainHandler.post {
                            result.error(
                                "JAR_BRIDGE_ERR",
                                error.toString(),
                                android.util.Log.getStackTraceString(error),
                            )
                        }
                    }
                }
            }
        }
    }

    private fun handle(activity: Activity, call: MethodCall): Any? {
        return when (call.method) {
            "load" -> load(
                activity = activity,
                dir = call.argument<String>("dir").orEmpty(),
                loadAsApk = call.argument<Boolean>("apk") == true,
            )

            "loadJar" -> withBridge { loadedBridge ->
                loadedBridge.loadJar(call.argument<String>("jarPath").orEmpty())
            }

            "createSpider" -> withBridge { loadedBridge ->
                loadedBridge.createSpider(
                    call.argument<String>("jarPath").orEmpty(),
                    call.argument<String>("siteKey").orEmpty(),
                    call.argument<String>("api").orEmpty(),
                    call.argument<String>("ext").orEmpty(),
                )
            }

            "call" -> withBridge { loadedBridge ->
                loadedBridge.call(
                    call.argument<String>("jarPath").orEmpty(),
                    call.argument<String>("siteKey").orEmpty(),
                    call.argument<String>("method").orEmpty(),
                    call.argument<List<String>>("args").orEmpty(),
                )
            }

            "proxy" -> withBridge { loadedBridge ->
                @Suppress("UNCHECKED_CAST")
                val params = (call.arguments as? Map<*, *>)
                    ?.get("params") as? Map<String, String>
                    ?: emptyMap()
                loadedBridge.proxy(
                    call.argument<String>("jarPath").orEmpty(),
                    params,
                )
            }

            "destroyJar" -> {
                bridge?.destroyJar(call.argument<String>("jarPath").orEmpty())
                mapOf("ok" to true)
            }

            "release" -> {
                release()
                mapOf("ok" to true)
            }

            else -> null
        }
    }

    private inline fun withBridge(block: (IJarSpiderBridge) -> Any?): Any {
        val loadedBridge = bridge ?: return bridgeNotLoaded()
        return block(loadedBridge) ?: mapOf(
            "ok" to false,
            "errorKind" to "EMPTY_RESULT",
            "error" to "JAR 插件桥返回空结果",
        )
    }

    @Synchronized
    private fun load(activity: Activity, dir: String, loadAsApk: Boolean): Map<String, Any> {
        if (loadAsApk) {
            return mapOf(
                "ok" to false,
                "errorKind" to "APK_MODE_UNSUPPORTED",
                "error" to "当前版本仅支持 import 模式的 JAR 插件",
            )
        }
        if (dir.isEmpty()) {
            return mapOf(
                "ok" to false,
                "errorKind" to "PLUGIN_NOT_READY",
                "error" to "JAR 插件目录为空",
            )
        }

        val pluginDir = File(dir)
        val dexFiles = pluginDir.listFiles()
            ?.filter { it.isFile && dexPattern.matcher(it.name).matches() }
            ?.sortedWith(
                compareBy<File> { dexSortKey(it) }.thenBy { it.name },
            )
            .orEmpty()
        if (dexFiles.isEmpty()) {
            return mapOf(
                "ok" to false,
                "errorKind" to "PLUGIN_NOT_READY",
                "error" to "JAR 插件缺少 classes.dex",
            )
        }

        val key = "$dir|${dexFiles.joinToString("|") { "${it.name}:${it.length()}" }}"
        if (bridge != null && bridgeKey == key) {
            return mapOf("ok" to true)
        }

        release()
        val optDir = File(activity.codeCacheDir, "jar_plugin").apply { mkdirs() }
        val loader = DexClassLoader(
            dexFiles.joinToString(File.pathSeparator) { it.absolutePath },
            optDir.absolutePath,
            File(pluginDir, "libs").absolutePath,
            IsolatedDependenciesClassLoader(
                JarSpiderHost::class.java.classLoader,
            ),
        )
        val instance = loader.loadClass(BRIDGE_CLASS)
            .getDeclaredConstructor()
            .newInstance()
        val loadedBridge = instance as IJarSpiderBridge
        loadedBridge.init(activity.applicationContext, optDir.absolutePath)
        bridge = loadedBridge
        bridgeKey = key
        return mapOf("ok" to true)
    }

    private fun dexSortKey(file: File): Int {
        if (file.name == "classes.dex") return 1
        val digits = file.name.removePrefix("classes").removeSuffix(".dex")
        return digits.toIntOrNull() ?: Int.MAX_VALUE
    }

    private fun bridgeNotLoaded(): Map<String, Any> = mapOf(
        "ok" to false,
        "errorKind" to "BRIDGE_NOT_LOADED",
        "error" to "JAR 插件桥未加载",
    )

    @Synchronized
    private fun release() {
        bridge = null
        bridgeKey = null
    }

    /**
     * DsPlayer JAR 插件自带 OkHttp/Okio，而 Flutter 应用的其他插件也可能带入
     * 不同版本。父 ClassLoader 必须隐藏这两组类，让插件从自身 classes.dex/JAR
     * 中加载成套版本，避免 Buffer/Source 等跨版本类型混淆。
     */
    private class IsolatedDependenciesClassLoader(base: ClassLoader) :
        ClassLoader(base) {
        override fun loadClass(name: String, resolve: Boolean): Class<*> {
            if (name.startsWith("okhttp3.") || name.startsWith("okio.")) {
                throw ClassNotFoundException(name)
            }
            return super.loadClass(name, resolve)
        }
    }
}
