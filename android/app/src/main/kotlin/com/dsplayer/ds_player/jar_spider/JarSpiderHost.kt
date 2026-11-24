package com.dsplayer.ds_player.jar_spider

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Flutter MethodChannel adapter for the isolated DsPlayer JAR process.
 *
 * This process never loads third-party DEX/JAR/native code. All JAR work is
 * delegated to :jar_spider, so a crash there cannot terminate Flutter.
 */
object JarSpiderHost {
    private const val CHANNEL = "com.dsplayer/jar_spider"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pool = Executors.newCachedThreadPool()

    private var channel: MethodChannel? = null

    fun register(activity: Activity, messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                pool.execute {
                    try {
                        val response = handle(activity, call)
                        mainHandler.post { result.success(response) }
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

    private fun handle(activity: Activity, call: MethodCall): Map<String, Any?> {
        val requestJson = JarBridgeJson.encodeRequest(call.method, call.arguments)
        val responseJson = JarSpiderProcessClient.call(
            activity.applicationContext ?: activity,
            requestJson,
        )
        return JarBridgeJson.decodeObject(responseJson)
    }
}
