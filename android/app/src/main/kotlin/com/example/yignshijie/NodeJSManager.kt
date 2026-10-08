package com.example.yuanying

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import fi.iki.elonen.NanoHTTPD
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class NodeJSManager private constructor(context: Context) {
    companion object {
        private const val TAG = "NodeJSManager"
        private var instance: NodeJSManager? = null

        @Synchronized
        fun getInstance(context: Context): NodeJSManager {
            if (instance == null) {
                instance = NodeJSManager(context.applicationContext)
            }
            return instance!!
        }

        private val mainHandler = Handler(Looper.getMainLooper())

        // ===== JNI 方法声明（新增 projectDir 参数）=====
        @JvmStatic
        external fun nodeStart(args: Array<String>, projectDir: String): Int
    }

    private val appContext: Context = context

    @Volatile var isRunning = false;        private set
    @Volatile var isNodeReady = false;      private set
    @Volatile var nativeServerPort = 0;     private set
    @Volatile var managementPort = 0;       private set
    @Volatile var spiderPort = 0;           private set

    private var webServer: NanoHTTPD? = null

    var onPortReceived: ((port: Int, type: String) -> Unit)? = null
    var onNodeReady: (() -> Unit)? = null

    init {
        System.loadLibrary("node")
        System.loadLibrary("native-lib")
        startLocalWebServer()
    }

    // ============================================================
    //  本地 HTTP 服务器（NanoHTTPD）
    // ============================================================
    private fun startLocalWebServer() {
        try {
            webServer = object : NanoHTTPD(0) {
                override fun serve(session: IHTTPSession): Response {
                    val uri = session.uri
                    val params = session.parms

                    return when (uri) {
                        "/onCatPawOpenPort" -> {
                            val port = params["port"]?.toIntOrNull() ?: 0
                            val type = params["type"] ?: "spider"
                            Log.i(TAG, "Port received: $port, type: $type")
                            mainHandler.post {
                                when (type) {
                                    "management" -> managementPort = port
                                    else -> spiderPort = port
                                }
                                onPortReceived?.invoke(port, type)
                            }
                            newFixedLengthResponse(Response.Status.OK, "text/plain", "OK")
                        }
                        "/onMessage" -> {
                            val body = try {
                                session.inputStream.bufferedReader().readText()
                            } catch (_: Exception) { "" }
                            try {
                                val json = JSONObject(body)
                                if (json.optString("message") == "ready") {
                                    isNodeReady = true
                                    mainHandler.post { onNodeReady?.invoke() }
                                }
                            } catch (_: Exception) {}
                            newFixedLengthResponse(Response.Status.OK, "text/plain", "OK")
                        }
                        else -> newFixedLengthResponse(
                            Response.Status.NOT_FOUND, "text/plain", "Not Found")
                    }
                }
            }
            webServer?.start()
            nativeServerPort = webServer?.listeningPort ?: 0
            Log.i(TAG, "Local server started on port: $nativeServerPort")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start local web server", e)
        }
    }

    fun getDocumentsSourcePath(): String {
        val sourcePath = File(appContext.filesDir, "nodejs-project/src/source")
        if (!sourcePath.exists()) sourcePath.mkdirs()
        return sourcePath.absolutePath
    }

    // ============================================================
    //  启动 Node.js
    // ============================================================
    fun startNodeJS(completion: ((Boolean) -> Unit)? = null) {
        // 已启动：重发端口回调（防止 Dart 侧错过），直接返回
        if (isRunning) {
            Log.i(TAG, "startNodeJS: already running, re-fire port callbacks")
            if (managementPort > 0) {
                mainHandler.post { onPortReceived?.invoke(managementPort, "management") }
            }
            if (spiderPort > 0) {
                mainHandler.post { onPortReceived?.invoke(spiderPort, "spider") }
            }
            if (isNodeReady) {
                mainHandler.post { onNodeReady?.invoke() }
            }
            completion?.invoke(true)
            return
        }

        if (webServer == null) {
            startLocalWebServer()
            if (webServer == null) {
                completion?.invoke(false)
                return
            }
        }

        Thread {
            try {
                val projectDir = File(appContext.filesDir, "nodejs-project")
                val distDir = File(projectDir, "dist")
                val scriptPath = File(distDir, "main.js")

                // 首次启动 or 旧版本残留 → 清空重拷
                if (!scriptPath.exists()) {
                    if (projectDir.exists()) {
                        Log.w(TAG, "Cleaning stale projectDir: ${projectDir.absolutePath}")
                        projectDir.deleteRecursively()
                    }
                    Log.i(TAG, "Copying assets -> ${projectDir.absolutePath}")
                    copyAssetsToDir("nodejs-project", projectDir)
                }

                if (!scriptPath.exists()) {
                    Log.e(TAG, "main.js STILL not found after copy!")
                    projectDir.walkTopDown().forEach {
                        Log.e(TAG, "  listing: ${it.absolutePath}")
                    }
                    mainHandler.post { completion?.invoke(false) }
                    return@Thread
                }

                // 确保 source 目录存在
                getDocumentsSourcePath()

                Log.i(TAG, "Starting Node.js: ${scriptPath.absolutePath}, native-port: $nativeServerPort")

                val args = arrayOf(
                    "node",
                    scriptPath.absolutePath,
                    "--native-port", nativeServerPort.toString()
                )

                isRunning = true
                mainHandler.post { completion?.invoke(true) }

                // node::Start 阻塞当前线程直到 Node 退出
                val result = nodeStart(args, projectDir.absolutePath)
                Log.i(TAG, "node::Start returned: $result")

                mainHandler.post {
                    isRunning = false
                    isNodeReady = false
                }

            } catch (e: Exception) {
                Log.e(TAG, "Failed to start Node.js", e)
                isRunning = false
                mainHandler.post { completion?.invoke(false) }
            }
        }.start()
    }

    // ============================================================
    //  递归拷贝 assets -> destDir
    //  修复：AssetManager.list() 对文件返回空数组 []，而非 null
    // ============================================================
    private fun copyAssetsToDir(assetPath: String, destDir: File) {
        val assetManager = appContext.assets
        destDir.mkdirs()

        val entries = assetManager.list(assetPath)
        if (entries == null || entries.isEmpty()) return

        for (entry in entries) {
            val srcPath = if (assetPath.isEmpty()) entry else "$assetPath/$entry"
            val destFile = File(destDir, entry)

            val subEntries = assetManager.list(srcPath)
            val isDir = subEntries != null && subEntries.isNotEmpty()

            if (isDir) {
                copyAssetsToDir(srcPath, destFile)
            } else {
                // list() 空数组可能是文件，也可能是空目录 → 用 open() 二次确认
                try {
                    assetManager.open(srcPath).use { input ->
                        destFile.parentFile?.mkdirs()
                        FileOutputStream(destFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                } catch (_: IOException) {
                    destFile.mkdirs()  // 空目录
                }
            }
        }
    }

    // ============================================================
    //  下载辅助
    // ============================================================
    private data class HttpResult(val code: Int, val body: String?)

    private fun downloadStringWithCode(url: String, timeoutMs: Int = 5000): HttpResult {
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.requestMethod = "GET"
            val code = conn.responseCode
            val body = if (code in 200..299) {
                conn.inputStream.bufferedReader().readText().trim()
            } else null
            conn.disconnect()
            HttpResult(code, body)
        } catch (e: Exception) {
            HttpResult(-1, null)
        }
    }

    private fun downloadString(url: String): String? {
        val r = downloadStringWithCode(url)
        return r.body
    }

    private fun downloadBytes(url: String): ByteArray? {
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            val bytes = conn.inputStream.readBytes()
            conn.disconnect()
            bytes
        } catch (_: Exception) { null }
    }

    private fun md5(bytes: ByteArray): String {
        val md = MessageDigest.getInstance("MD5")
        return md.digest(bytes).joinToString("") { "%02x".format(it) }
    }

    // ============================================================
    //  加载源
    // ============================================================
    fun loadSourceFromURL(urlString: String, completion: ((Boolean, String?) -> Unit)? = null) {
        Log.i(TAG, "loadSourceFromURL: $urlString")

        var normalizedUrl = urlString
        if (normalizedUrl.endsWith(".js.md5")) {
            normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 4)
        }

        Thread {
            try {
                val sourcePath = getDocumentsSourcePath()
                val sourceDir = File(sourcePath)
                val indexJs = File(sourceDir, "index.js")
                val indexMd5 = File(sourceDir, "index.js.md5")
                val configJs = File(sourceDir, "index.config.js")
                val configMd5 = File(sourceDir, "index.config.js.md5")

                // ---------- 缓存检查（对齐 iOS：404 时用缓存）----------
                var useCache = false
                if (indexJs.exists() && indexMd5.exists()) {
                    Log.i(TAG, "Cache exists, checking remote MD5...")
                    val r = downloadStringWithCode("$normalizedUrl.md5")
                    when {
                        r.code == 404 -> {
                            Log.i(TAG, "Remote MD5 404 -> use cached source")
                            useCache = true
                        }
                        r.code in 200..299 && !r.body.isNullOrEmpty() -> {
                            val localMd5 = indexMd5.readText().trim()
                            if (r.body == localMd5) {
                                Log.i(TAG, "MD5 match -> use cached source")
                                useCache = true
                            } else {
                                Log.i(TAG, "MD5 mismatch: local=$localMd5 remote=${r.body}")
                            }
                        }
                        else -> Log.w(TAG, "Fetch remote MD5 failed (code=${r.code})")
                    }
                }

                if (!useCache) {
                    Log.i(TAG, "Downloading source: $normalizedUrl")
                    val jsData = downloadBytes(normalizedUrl)
                    if (jsData == null) {
                        mainHandler.post { completion?.invoke(false, "Failed to download index.js") }
                        return@Thread
                    }

                    val md5Resp = downloadStringWithCode("$normalizedUrl.md5")
                    if (md5Resp.code in 200..299 && !md5Resp.body.isNullOrEmpty()) {
                        val actualMd5 = md5(jsData)
                        if (actualMd5 != md5Resp.body) {
                            mainHandler.post { completion?.invoke(false, "MD5 verification failed") }
                            return@Thread
                        }
                        sourceDir.mkdirs()
                        FileOutputStream(indexMd5).use { it.write(md5Resp.body.toByteArray()) }
                    }

                    sourceDir.mkdirs()
                    FileOutputStream(indexJs).use { it.write(jsData) }

                    // index.config.js（可选）
                    try {
                        val configUrl = normalizedUrl.replace("/index.js", "/index.config.js")
                        val configData = downloadBytes(configUrl)
                        if (configData != null) {
                            FileOutputStream(configJs).use { it.write(configData) }
                            val cm = downloadStringWithCode("$configUrl.md5")
                            if (cm.code in 200..299 && !cm.body.isNullOrEmpty()) {
                                FileOutputStream(configMd5).use { it.write(cm.body.toByteArray()) }
                            }
                        }
                    } catch (_: Exception) {
                        Log.w(TAG, "index.config.js not available, skip")
                    }
                    Log.i(TAG, "Download completed")
                }

                sendLoadCommandToNodeJS(sourcePath) { ok, msg ->
                    mainHandler.post { completion?.invoke(ok, msg) }
                }

            } catch (e: Exception) {
                Log.e(TAG, "loadSourceFromURL error", e)
                mainHandler.post { completion?.invoke(false, e.message) }
            }
        }.start()
    }

    // ============================================================
    //  通知 Node 加载源（POST /source/loadPath）
    // ============================================================
    private fun sendLoadCommandToNodeJS(path: String, completion: ((Boolean, String?) -> Unit)?) {
        sendLoadCommandToNodeJS(path, 3, completion)
    }

    private fun sendLoadCommandToNodeJS(path: String, retryCount: Int,
                                        completion: ((Boolean, String?) -> Unit)?) {
        if (managementPort <= 0) {
            if (retryCount > 0) {
                mainHandler.postDelayed({
                    sendLoadCommandToNodeJS(path, retryCount - 1, completion)
                }, 2000)
                return
            }
            completion?.invoke(false, "Management port not ready")
            return
        }

        Thread {
            try {
                val url = URL("http://127.0.0.1:$managementPort/source/loadPath")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.connectTimeout = 15000
                conn.readTimeout = 15000

                val body = JSONObject().apply { put("path", path) }
                conn.outputStream.use { it.write(body.toString().toByteArray()) }

                val code = conn.responseCode
                conn.disconnect()

                if (code in 200..299) {
                    Log.i(TAG, "sendLoadCommandToNodeJS OK")
                    completion?.invoke(true, "Source loaded successfully")
                } else {
                    if (retryCount > 0) {
                        mainHandler.postDelayed({
                            sendLoadCommandToNodeJS(path, retryCount - 1, completion)
                        }, 2000)
                    } else {
                        completion?.invoke(false, "Server error: $code")
                    }
                }
            } catch (e: Exception) {
                if (retryCount > 0) {
                    mainHandler.postDelayed({
                        sendLoadCommandToNodeJS(path, retryCount - 1, completion)
                    }, 2000)
                } else {
                    completion?.invoke(false, e.message)
                }
            }
        }.start()
    }

    fun deleteSource(completion: ((Boolean) -> Unit)? = null) {
        try {
            val sourcePath = File(getDocumentsSourcePath())
            if (sourcePath.exists()) sourcePath.deleteRecursively()
            spiderPort = 0
            completion?.invoke(true)
        } catch (e: Exception) {
            completion?.invoke(false)
        }
    }

    /**
     * 软停止：
     * Android 的 node::Start 是同进程阻塞调用，无法在进程内真正停止。
     * 只清软状态，保留 webServer / 端口 / Node 运行状态，方便 Dart 侧复用。
     */
    fun stopNodeJS() {
        Log.i(TAG, "stopNodeJS: soft reset (Node keeps running)")
        isNodeReady = false
    }
}