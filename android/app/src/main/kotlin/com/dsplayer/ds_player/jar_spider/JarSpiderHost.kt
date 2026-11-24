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

    private var bridge: Any? = null
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
                invokeBridge(
                    loadedBridge,
                    "loadJar",
                    String::class.java to call.argument<String>("jarPath").orEmpty(),
                )
            }

            "createSpider" -> withBridge { loadedBridge ->
                invokeBridge(
                    loadedBridge,
                    "createSpider",
                    String::class.java to call.argument<String>("jarPath").orEmpty(),
                    String::class.java to call.argument<String>("siteKey").orEmpty(),
                    String::class.java to call.argument<String>("api").orEmpty(),
                    String::class.java to call.argument<String>("ext").orEmpty(),
                )
            }

            "call" -> withBridge { loadedBridge ->
                invokeBridge(
                    loadedBridge,
                    "call",
                    String::class.java to call.argument<String>("jarPath").orEmpty(),
                    String::class.java to call.argument<String>("siteKey").orEmpty(),
                    String::class.java to call.argument<String>("method").orEmpty(),
                    List::class.java to call.argument<List<String>>("args").orEmpty(),
                )
            }

            "proxy" -> withBridge { loadedBridge ->
                @Suppress("UNCHECKED_CAST")
                val params = (call.arguments as? Map<*, *>)
                    ?.get("params") as? Map<String, String>
                    ?: emptyMap()
                invokeBridge(
                    loadedBridge,
                    "proxy",
                    String::class.java to call.argument<String>("jarPath").orEmpty(),
                    Map::class.java to params,
                )
            }

            "destroyJar" -> {
                bridge?.let { loadedBridge ->
                    invokeBridge(
                        loadedBridge,
                        "destroyJar",
                        String::class.java to
                            call.argument<String>("jarPath").orEmpty(),
                    )
                }
                mapOf("ok" to true)
            }

            "release" -> {
                release()
                mapOf("ok" to true)
            }

            else -> null
        }
    }

    private inline fun withBridge(block: (Any) -> Any?): Any {
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
            JarSpiderHost::class.java.classLoader,
        )
        val instance = loader.loadClass(BRIDGE_CLASS)
            .getDeclaredConstructor()
            .newInstance()
        invokeBridge(
            instance,
            "init",
            android.content.Context::class.java to activity.applicationContext,
            String::class.java to optDir.absolutePath,
        )
        bridge = instance
        bridgeKey = key
        return mapOf("ok" to true)
    }

    private fun dexSortKey(file: File): Int {
        if (file.name == "classes.dex") return 1
        val digits = file.name.removePrefix("classes").removeSuffix(".dex")
        return digits.toIntOrNull() ?: Int.MAX_VALUE
    }

    private fun invokeBridge(
        target: Any,
        methodName: String,
        vararg args: Pair<Class<*>, Any?>,
    ): Any? {
        val method = target.javaClass.getMethod(
            methodName,
            *args.map { it.first }.toTypedArray(),
        )
        return method.invoke(target, *args.map { it.second }.toTypedArray())
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
}
