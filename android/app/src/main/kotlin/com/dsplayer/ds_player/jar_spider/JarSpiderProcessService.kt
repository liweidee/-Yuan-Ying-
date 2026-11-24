package com.dsplayer.ds_player.jar_spider

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Process
import android.os.RemoteException
import android.util.Log

/**
 * Isolated process that owns all third-party JAR execution.
 *
 * The main process only talks to this service through AIDL. If a JAR exits,
 * aborts or crashes its native runtime, Android terminates only this process.
 */
class JarSpiderProcessService : Service() {
    companion object {
        private const val TAG = "JarSpiderProcess"
    }

    private lateinit var workerThread: HandlerThread
    private lateinit var workerHandler: Handler
    private lateinit var runtime: JarSpiderRuntime

    private val binder = object : IJarSpiderProcess.Stub() {
        override fun call(
            requestId: String,
            requestJson: String,
            callback: IJarSpiderProcessCallback,
        ) {
            workerHandler.post {
                val response = try {
                    runtime.handleRequest(requestJson)
                } catch (error: Throwable) {
                    Log.e(TAG, "Unexpected JAR worker failure", error)
                    JarBridgeJson.encodeFailure(
                        "JAR_PROCESS_ERROR",
                        error.toString(),
                        Log.getStackTraceString(error),
                    )
                }
                try {
                    callback.onResult(requestId, response)
                } catch (error: RemoteException) {
                    Log.w(TAG, "JAR result callback is gone", error)
                }
            }
        }

        override fun abort() {
            Log.w(TAG, "Aborting JAR process on request timeout")
            Process.killProcess(Process.myPid())
        }
    }

    override fun onCreate() {
        super.onCreate()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            Log.e(
                TAG,
                "Uncaught exception in isolated JAR thread=${thread.name}",
                error,
            )
            Process.killProcess(Process.myPid())
        }

        workerThread = HandlerThread("jar-spider-worker").apply { start() }
        workerHandler = Handler(workerThread.looper)
        runtime = JarSpiderRuntime(applicationContext)
        Log.i(TAG, "Isolated JAR process started pid=${Process.myPid()}")
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        workerHandler.post { runCatching { runtime.release() } }
        workerThread.quitSafely()
        super.onDestroy()
    }
}
