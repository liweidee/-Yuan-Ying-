package com.dsplayer.ds_player.jar_spider

import android.content.Context
import android.util.Log
import dalvik.system.DexClassLoader
import org.json.JSONObject
import java.io.File
import java.util.regex.Pattern

/**
 * JAR runtime used only inside the dedicated :jar_spider process.
 *
 * All dynamic code, network work and native libraries stay in this process so
 * third-party JAR failures cannot terminate the Flutter application process.
 */
internal class JarSpiderRuntime(context: Context) {
    companion object {
        private const val TAG = "JarSpider"
        private const val BRIDGE_CLASS = "com.dsplayer.plugin.jar.JarSpiderBridge"
        private const val DEX_PATTERN = "classes\\d*\\.dex"
    }

    private val appContext = context.applicationContext ?: context
    private val dexPattern = Pattern.compile(DEX_PATTERN)

    private var bridge: IJarSpiderBridge? = null
    private var bridgeKey: String? = null

    init {
        logDependencyBaseline()
    }

    @Synchronized
    fun handleRequest(requestJson: String): String {
        return try {
            val request = JSONObject(requestJson)
            val method = request.optString("method")
            val arguments = request.optJSONObject("arguments")
                ?.let { JarBridgeJson.decodeObject(it.toString()) }
                ?: emptyMap()
            val value = handle(method, arguments)
            if (value is Map<*, *> && value["ok"] is Boolean) {
                JarBridgeJson.encodeBridgeResult(value)
            } else {
                JarBridgeJson.encodeSuccess(value)
            }
        } catch (error: Throwable) {
            Log.e(TAG, "JAR runtime request failed", error)
            JarBridgeJson.encodeFailure(
                "JAR_RUNTIME_ERR",
                error.toString(),
                Log.getStackTraceString(error),
            )
        }
    }

    private fun handle(method: String, arguments: Map<String, Any?>): Any? {
        return when (method) {
            "load" -> load(
                dir = arguments.string("dir"),
                loadAsApk = arguments.boolean("apk"),
            )

            "loadJar" -> withBridge { loadedBridge ->
                loadedBridge.loadJar(arguments.string("jarPath"))
            }

            "createSpider" -> withBridge { loadedBridge ->
                loadedBridge.createSpider(
                    arguments.string("jarPath"),
                    arguments.string("siteKey"),
                    arguments.string("api"),
                    arguments.string("ext"),
                )
            }

            "call" -> withBridge { loadedBridge ->
                loadedBridge.call(
                    arguments.string("jarPath"),
                    arguments.string("siteKey"),
                    arguments.string("method"),
                    arguments.stringList("args"),
                )
            }

            "proxy" -> withBridge { loadedBridge ->
                loadedBridge.proxy(
                    arguments.string("jarPath"),
                    arguments.stringMap("params"),
                )
            }

            "destroyJar" -> {
                bridge?.destroyJar(arguments.string("jarPath"))
                mapOf("ok" to true)
            }

            "release" -> {
                release()
                mapOf("ok" to true)
            }

            else -> mapOf(
                "ok" to false,
                "errorKind" to "UNKNOWN_METHOD",
                "error" to "未知 JAR 通道方法：$method",
            )
        }
    }

    @Synchronized
    private fun load(dir: String, loadAsApk: Boolean): Map<String, Any> {
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
        val optDir = File(appContext.codeCacheDir, "jar_plugin").apply { mkdirs() }
        val loader = DexClassLoader(
            dexFiles.joinToString(File.pathSeparator) { it.absolutePath },
            optDir.absolutePath,
            File(pluginDir, "libs").absolutePath,
            JarSpiderRuntime::class.java.classLoader,
        )
        val instance = loader.loadClass(BRIDGE_CLASS)
            .getDeclaredConstructor()
            .newInstance()
        val loadedBridge = instance as IJarSpiderBridge
        loadedBridge.init(appContext, optDir.absolutePath)
        bridge = loadedBridge
        bridgeKey = key
        return mapOf("ok" to true)
    }

    private fun dexSortKey(file: File): Int {
        if (file.name == "classes.dex") return 1
        val digits = file.name.removePrefix("classes").removeSuffix(".dex")
        return digits.toIntOrNull() ?: Int.MAX_VALUE
    }

    private inline fun withBridge(block: (IJarSpiderBridge) -> Any?): Any {
        val loadedBridge = bridge ?: return mapOf(
            "ok" to false,
            "errorKind" to "BRIDGE_NOT_LOADED",
            "error" to "JAR 插件桥未加载",
        )
        return block(loadedBridge) ?: mapOf(
            "ok" to false,
            "errorKind" to "EMPTY_RESULT",
            "error" to "JAR 插件桥返回空结果",
        )
    }

    @Synchronized
    fun release() {
        bridge = null
        bridgeKey = null
    }

    private fun logDependencyBaseline() {
        val loader = JarSpiderRuntime::class.java.classLoader
        val status = listOf(
            "okhttp3.Request\$Builder",
            "okio.Buffer",
            "com.google.gson.Gson",
            "kotlin.Result",
        ).joinToString { className ->
            val available = runCatching {
                Class.forName(className, false, loader)
            }.isSuccess
            "$className=${if (available) "ok" else "missing"}"
        }
        Log.i(TAG, "JAR dependency baseline: $status")
    }
}

private fun Map<String, Any?>.string(key: String): String {
    return this[key]?.toString().orEmpty()
}

private fun Map<String, Any?>.boolean(key: String): Boolean {
    return when (val value = this[key]) {
        is Boolean -> value
        is Number -> value.toInt() != 0
        is String -> value.equals("true", ignoreCase = true)
        else -> false
    }
}

private fun Map<String, Any?>.stringList(key: String): List<String> {
    return (this[key] as? List<*>)
        ?.mapNotNull { it?.toString() }
        .orEmpty()
}

private fun Map<String, Any?>.stringMap(key: String): Map<String, String> {
    return (this[key] as? Map<*, *>)
        ?.entries
        ?.mapNotNull { entry ->
            val mapKey = entry.key?.toString() ?: return@mapNotNull null
            val mapValue = entry.value?.toString() ?: return@mapNotNull null
            mapKey to mapValue
        }
        ?.toMap()
        .orEmpty()
}
