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

        // ===== JNI 方法声明 =====
        @JvmStatic
        external fun nodeStart(args: Array<String>): Int
    }

    private val appContext: Context = context

    @Volatile
    var isRunning = false
        private set
    @Volatile
    var isNodeReady = false
        private set
    @Volatile
    var nativeServerPort = 0
        private set
    @Volatile
    var managementPort = 0
        private set
    @Volatile
    var spiderPort = 0
        private set

    private var webServer: NanoHTTPD? = null

    var onPortReceived: ((port: Int, type: String) -> Unit)? = null
    var onNodeReady: (() -> Unit)? = null

    init {
        System.loadLibrary("node")
        System.loadLibrary("native-lib")
        startLocalWebServer()
    }

    // ============================================================
    // 本地 HTTP 服务器
    // ============================================================
    private fun startLocalWebServer() {
        try {
            webServer = object : NanoHTTPD(0) {
                override fun serve(session: IHTTPSession): Response {
                    val uri = session.uri
                    val params = session.parms

                    return when {
                        uri == "/onCatPawOpenPort" -> {
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

                        uri == "/onMessage" -> {
                            val body = session.inputStream.bufferedReader().readText()
                            try {
                                val json = JSONObject(body)
                                val message = json.optString("message")
                                if (message == "ready") {
                                    isNodeReady = true
                                    mainHandler.post {
                                        onNodeReady?.invoke()
                                    }
                                }
                            } catch (_: Exception) {}
                            newFixedLengthResponse(Response.Status.OK, "text/plain", "OK")
                        }

                        else -> newFixedLengthResponse(Response.Status.NOT_FOUND, "text/plain", "Not Found")
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
        if (!sourcePath.exists()) {
            sourcePath.mkdirs()
        }
        return sourcePath.absolutePath
    }

    // ============================================================
    // 启动 Node.js
    // ============================================================
    fun startNodeJS(completion: ((Boolean) -> Unit)? = null) {
        if (isRunning) {
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
                if (!projectDir.exists()) {
                    copyAssetsToDir("nodejs-project/dist", projectDir)
                }

                val scriptPath = File(projectDir, "dist/main.js")
                if (!scriptPath.exists()) {
                    Log.e(TAG, "Node.js script not found: ${scriptPath.absolutePath}")
                    mainHandler.post { completion?.invoke(false) }
                    return@Thread
                }

                val sourcePath = getDocumentsSourcePath()
                Log.i(TAG, "Starting Node.js: ${scriptPath.absolutePath}, native-port: $nativeServerPort")

                val args = arrayOf(
                    "node",
                    "--security-revert=CVE-2023-46809",
                    scriptPath.absolutePath,
                    "--native-port", nativeServerPort.toString()
                )

                isRunning = true
                mainHandler.post { completion?.invoke(true) }

                val result = nodeStart(args)
                Log.i(TAG, "node_start returned: $result")

                mainHandler.post {
                    isRunning = false
                    isNodeReady = false
                    webServer?.stop()
                }

            } catch (e: Exception) {
                Log.e(TAG, "Failed to start Node.js", e)
                isRunning = false
                mainHandler.post { completion?.invoke(false) }
            }
        }.start()
    }

    // ============================================================
    // 从 assets 复制文件（修复递归逻辑）
    // ============================================================
    private fun copyAssetsToDir(assetPath: String, destDir: File) {
        destDir.mkdirs()
        val assetManager = appContext.assets
        val entries = assetManager.list(assetPath) ?: return

        for (entry in entries) {
            val srcPath = if (assetPath.isNotEmpty()) "$assetPath/$entry" else entry
            val destFile = File(destDir, entry)

            // 检查 asset 路径是否指向一个目录
            // 在 Android assets 中，没有直接的 isDirectory() 方法，
            // 但可以通过尝试列出其内容来判断。
            // 如果 list 返回非空数组，则视为目录。
            val subEntries = assetManager.list(srcPath)
            if (subEntries != null) {
                // 这是一个目录：递归复制
                copyAssetsToDir(srcPath, destFile)
            } else {
                // 这是一个文件：复制
                try {
                    val inputStream = assetManager.open(srcPath)
                    FileOutputStream(destFile).use { output ->
                        inputStream.copyTo(output)
                    }
                    inputStream.close()
                } catch (e: IOException) {
                    Log.e(TAG, "Failed to copy file: $srcPath", e)
                }
            }
        }
    }

    // ============================================================
    // 下载辅助方法
    // ============================================================
    private fun downloadString(url: String): String? {
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.inputStream.bufferedReader().readText().trim().also {
                connection.disconnect()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun downloadBytes(url: String): ByteArray? {
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            connection.inputStream.readBytes().also {
                connection.disconnect()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun md5(bytes: ByteArray): String {
        val md = MessageDigest.getInstance("MD5")
        val digest = md.digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    // ============================================================
    // 加载源
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
                val indexJs = File(sourcePath, "index.js")
                val indexMd5 = File(sourcePath, "index.js.md5")
                val configJs = File(sourcePath, "index.config.js")
                val configMd5 = File(sourcePath, "index.config.js.md5")

                var useCache = false
                if (indexJs.exists() && indexMd5.exists()) {
                    Log.i(TAG, "Cache exists, checking MD5...")
                    val remoteMd5 = downloadString("$normalizedUrl.md5")
                    if (remoteMd5 != null) {
                        val localMd5 = indexMd5.readText().trim()
                        if (remoteMd5 == localMd5) {
                            Log.i(TAG, "✅ MD5 match! Using cached source")
                            useCache = true
                        } else {
                            Log.i(TAG, "MD5 mismatch: local=$localMd5, remote=$remoteMd5")
                        }
                    } else {
                        Log.w(TAG, "Failed to download remote MD5, will re-download")
                    }
                }

                if (!useCache) {
                    Log.i(TAG, "Downloading source from: $normalizedUrl")

                    val jsData = downloadBytes(normalizedUrl)
                    if (jsData == null) {
                        mainHandler.post { completion?.invoke(false, "Failed to download index.js") }
                        return@Thread
                    }

                    val remoteMd5 = downloadString("$normalizedUrl.md5")
                    if (remoteMd5 != null) {
                        val actualMd5 = md5(jsData)
                        if (actualMd5 != remoteMd5) {
                            mainHandler.post { completion?.invoke(false, "MD5 verification failed") }
                            return@Thread
                        }
                        FileOutputStream(indexMd5).use { it.write(remoteMd5.toByteArray()) }
                    }

                    FileOutputStream(indexJs).use { it.write(jsData) }

                    val configUrl = normalizedUrl.replace("/index.js", "/index.config.js")
                    try {
                        val configData = downloadBytes(configUrl)
                        if (configData != null) {
                            FileOutputStream(configJs).use { it.write(configData) }
                            val configMd5Data = downloadString("$configUrl.md5")
                            if (configMd5Data != null) {
                                FileOutputStream(configMd5).use { it.write(configMd5Data.toByteArray()) }
                            }
                        }
                    } catch (_: Exception) {
                        Log.w(TAG, "Config file not found, skipping")
                    }

                    Log.i(TAG, "Download completed")
                }

                sendLoadCommandToNodeJS(sourcePath) { success, message ->
                    mainHandler.post {
                        completion?.invoke(success, message)
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "loadSourceFromURL error", e)
                mainHandler.post {
                    completion?.invoke(false, e.message)
                }
            }
        }.start()
    }

    // ============================================================
    // 发送加载命令
    // ============================================================
    private fun sendLoadCommandToNodeJS(path: String, completion: ((Boolean, String?) -> Unit)? = null) {
        sendLoadCommandToNodeJS(path, 3, completion)
    }

    private fun sendLoadCommandToNodeJS(path: String, retryCount: Int, completion: ((Boolean, String?) -> Unit)? = null) {
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
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json")
                connection.doOutput = true
                connection.connectTimeout = 15000
                connection.readTimeout = 15000

                val body = JSONObject().apply {
                    put("path", path)
                }
                connection.outputStream.use { output ->
                    output.write(body.toString().toByteArray())
                }

                val responseCode = connection.responseCode
                if (responseCode in 200..299) {
                    completion?.invoke(true, "Source loaded successfully")
                } else {
                    completion?.invoke(false, "Server error: $responseCode")
                }
                connection.disconnect()

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
        val sourcePath = File(getDocumentsSourcePath())
        try {
            if (sourcePath.exists()) {
                sourcePath.deleteRecursively()
            }
            spiderPort = 0
            completion?.invoke(true)
        } catch (e: Exception) {
            completion?.invoke(false)
        }
    }

    fun stopNodeJS() {
        isRunning = false
        isNodeReady = false
        webServer?.stop()
        webServer = null
        nativeServerPort = 0
        managementPort = 0
        spiderPort = 0
    }
}