package com.dsplayer.ds_player.jar_spider

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.RemoteException
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * Main-process Binder proxy for the isolated JAR runtime.
 */
internal object JarSpiderProcessClient {
    private const val TAG = "JarSpiderProcess"
    private const val BIND_TIMEOUT_MS = 10_000L
    private const val CALL_TIMEOUT_MS = 90_000L

    private val bindLock = Any()
    private val pendingRequests = ConcurrentHashMap<String, PendingRequest>()
    private val nextRequestId = AtomicLong(0)
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var service: IJarSpiderProcess? = null

    private var connection: Connection? = null
    fun call(context: Context, requestJson: String): String {
        val remote = ensureBound(context)
            ?: return JarBridgeJson.encodeFailure(
                "JAR_PROCESS_UNAVAILABLE",
                "JAR 运行进程启动失败",
            )

        val requestId = nextRequestId.incrementAndGet().toString()
        val pending = PendingRequest()
        pendingRequests[requestId] = pending

        val callback = object : IJarSpiderProcessCallback.Stub() {
            override fun onResult(
                responseRequestId: String,
                responseJson: String,
            ) {
                if (responseRequestId != requestId) return
                val request = pendingRequests.remove(requestId) ?: return
                request.complete(responseJson)
            }
        }

        val timeoutTask = Runnable {
            val request = pendingRequests.remove(requestId) ?: return@Runnable
            request.complete(
                JarBridgeJson.encodeFailure(
                    "JAR_PROCESS_TIMEOUT",
                    "JAR 调用超时，运行进程已被隔离终止",
                ),
            )
            runCatching { remote.abort() }
        }
        mainHandler.postDelayed(timeoutTask, CALL_TIMEOUT_MS)

        return try {
            remote.call(requestId, requestJson, callback)
            val response = pending.await(CALL_TIMEOUT_MS + 2_000L)
            mainHandler.removeCallbacks(timeoutTask)
            if (response != null) {
                response
            } else {
                pendingRequests.remove(requestId)
                runCatching { remote.abort() }
                JarBridgeJson.encodeFailure(
                    "JAR_PROCESS_TIMEOUT",
                    "JAR 调用超时，运行进程已被隔离终止",
                )
            }
        } catch (error: RemoteException) {
            pendingRequests.remove(requestId)
            mainHandler.removeCallbacks(timeoutTask)
            failAll("JAR_PROCESS_CRASHED", "JAR 运行进程已异常退出")
            JarBridgeJson.encodeFailure(
                "JAR_PROCESS_CRASHED",
                error.toString(),
            )
        } catch (error: Throwable) {
            pendingRequests.remove(requestId)
            mainHandler.removeCallbacks(timeoutTask)
            JarBridgeJson.encodeFailure(
                "JAR_PROCESS_ERROR",
                error.toString(),
            )
        }
    }

    private fun ensureBound(context: Context): IJarSpiderProcess? {
        service?.let { existing ->
            if (existing.asBinder().isBinderAlive) {
                return existing
            }
        }

        val application = context.applicationContext ?: context
        var waitConnection: Connection? = null
        synchronized(bindLock) {
            val currentService = service
            if (currentService != null && currentService.asBinder().isBinderAlive) {
                return currentService
            }

            appContext = application
            val existingConnection = connection
            if (existingConnection == null) {
                val newConnection = Connection()
                connection = newConnection
                waitConnection = newConnection
                val intent = Intent(application, JarSpiderProcessService::class.java)
                val bound = runCatching {
                    application.bindService(
                        intent,
                        newConnection,
                        Context.BIND_AUTO_CREATE,
                    )
                }.getOrElse { error ->
                    Log.e(TAG, "bind JAR process failed", error)
                    false
                }
                if (!bound) {
                    connection = null
                    newConnection.ready.countDown()
                    return null
                }
            } else {
                waitConnection = existingConnection
            }
        }

        val latch = waitConnection?.ready ?: return null
        if (!runCatching {
                latch.await(BIND_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            }.getOrDefault(false)
        ) {
            Log.e(TAG, "Timed out waiting for JAR process")
            return null
        }

        return service?.takeIf { it.asBinder().isBinderAlive }
    }

    private fun handleRemoteDeath(source: Connection? = null) {
        var isCurrentConnection = false
        val oldConnection = synchronized(bindLock) {
            if (source == null || connection === source) {
                isCurrentConnection = true
                val previous = connection
                connection = null
                previous
            } else {
                null
            }
        }
        if (!isCurrentConnection) return

        Log.e(TAG, "JAR process disconnected")
        service = null
        failAll("JAR_PROCESS_CRASHED", "JAR 运行进程已异常退出")
        oldConnection?.ready?.countDown()
        mainHandler.post {
            if (oldConnection != null) {
                runCatching { appContext?.unbindService(oldConnection) }
            }
        }
    }

    private fun failAll(kind: String, message: String) {
        val response = JarBridgeJson.encodeFailure(kind, message)
        val iterator = pendingRequests.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (pendingRequests.remove(entry.key, entry.value)) {
                entry.value.complete(response)
            }
        }
    }

    private inner class Connection : ServiceConnection {
        val ready = CountDownLatch(1)

        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val isCurrentConnection = synchronized(bindLock) {
                connection === this
            }
            if (!isCurrentConnection) {
                ready.countDown()
                return
            }
            if (binder == null) {
                onNullBinding(name)
                return
            }
            val proxy = IJarSpiderProcess.Stub.asInterface(binder)
            val recipient = IBinder.DeathRecipient { handleRemoteDeath(this) }
            try {
                binder.linkToDeath(recipient, 0)
                service = proxy
                Log.i(TAG, "Connected to isolated JAR process")
            } catch (error: RemoteException) {
                Log.e(TAG, "Link JAR process death failed", error)
                service = null
                handleRemoteDeath(this)
                return
            }
            ready.countDown()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            handleRemoteDeath(this)
        }

        override fun onBindingDied(name: ComponentName?) {
            handleRemoteDeath(this)
        }

        override fun onNullBinding(name: ComponentName?) {
            Log.e(TAG, "JAR process returned a null binding")
            val isCurrentConnection = synchronized(bindLock) {
                if (connection === this) {
                    connection = null
                    true
                } else {
                    false
                }
            }
            ready.countDown()
            if (!isCurrentConnection) return
            service = null
            failAll("JAR_PROCESS_UNAVAILABLE", "JAR 运行进程无法启动")
            mainHandler.post {
                runCatching { appContext?.unbindService(this) }
            }
        }
    }

    private class PendingRequest {
        private val latch = CountDownLatch(1)

        @Volatile
        private var response: String? = null

        fun complete(value: String) {
            response = value
            latch.countDown()
        }

        fun await(timeoutMs: Long): String? {
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            return response
        }
    }
}
