package com.example.yuanying

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Process
import android.widget.Toast
import java.io.File

/**
 * 通用服务托管前台服务。
 *
 * - 沙盒子进程和猫影视 Node 使用独立的 PID 状态，互不覆盖。
 * - 猫影视 Node 重启期间 active=true、pid=0，通知栏保持前台服务。
 * - 通知栏“全部停止”会记录主动停止标记，避免 Dart 端误判为崩溃后重启。
 */
class ServiceHostService : Service() {

    companion object {
        const val ACTION_UPDATE_SANDBOX = "com.example.yuanying.services.UPDATE_SANDBOX"
        const val ACTION_UPDATE_CATVOD = "com.example.yuanying.services.UPDATE_CATVOD"
        const val ACTION_STOP_ALL = "com.example.yuanying.services.STOP_ALL"
        const val ACTION_COPY_GW = "com.example.yuanying.services.COPY_GW"

        const val EXTRA_PIDS = "pids"
        const val EXTRA_COUNT = "count"
        const val EXTRA_SERVICES = "services"
        const val EXTRA_PLUGINS = "plugins"
        const val EXTRA_GW = "gw"
        const val EXTRA_URL = "url"
        const val EXTRA_CATVOD_ACTIVE = "catvod_active"
        const val EXTRA_CATVOD_PID = "catvod_pid"

        const val PREFS_NAME = "service_host_state"
        const val PREF_CATVOD_STOP_REQUESTED = "catvod_node_stop_requested"

        private const val CHANNEL_ID = "service_host"
        private const val NOTIFICATION_ID = 0x5948

        @Volatile
        private var sandboxPids: Array<Int> = emptyArray()

        @Volatile
        private var sandboxServices = -1

        @Volatile
        private var sandboxPlugins = -1

        @Volatile
        private var gateway: String? = null

        @Volatile
        private var catVodActive = false

        @Volatile
        private var catVodPid = 0

        private fun isProcessAlive(pid: Int): Boolean {
            return try {
                File("/proc/$pid").exists()
            } catch (_: Throwable) {
                false
            }
        }

        private fun allPids(): IntArray {
            return buildList {
                addAll(sandboxPids.toList())
                if (catVodPid > 0) add(catVodPid)
            }.distinct().toIntArray()
        }

        private fun clearState() {
            sandboxPids = emptyArray()
            sandboxServices = -1
            sandboxPlugins = -1
            gateway = null
            catVodActive = false
            catVodPid = 0
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (ACTION_STOP_ALL == action) {
            val captured = allPids()
            if (catVodActive || catVodPid > 0) {
                getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    .edit()
                    .putBoolean(PREF_CATVOD_STOP_REQUESTED, true)
                    .commit()
            }
            clearState()
            stopPids(captured)
            stopForegroundAndSelf()
            return START_NOT_STICKY
        }

        if (ACTION_COPY_GW == action) {
            val url = intent?.getStringExtra(EXTRA_URL)
            if (!url.isNullOrEmpty()) {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("gateway", url))
                Toast.makeText(applicationContext, "已复制 $url", Toast.LENGTH_SHORT).show()
            }
            return START_STICKY
        }

        when (action) {
            ACTION_UPDATE_SANDBOX -> {
                sandboxPids = intent
                    ?.getIntegerArrayListExtra(EXTRA_PIDS)
                    ?.toTypedArray()
                    ?: emptyArray()
                sandboxServices = intent?.getIntExtra(EXTRA_SERVICES, -1) ?: -1
                sandboxPlugins = intent?.getIntExtra(EXTRA_PLUGINS, -1) ?: -1
                gateway = intent?.getStringExtra(EXTRA_GW)?.takeIf { it.isNotEmpty() }
            }

            ACTION_UPDATE_CATVOD -> {
                catVodActive = intent?.getBooleanExtra(EXTRA_CATVOD_ACTIVE, false) ?: false
                catVodPid = if (catVodActive) {
                    intent?.getIntExtra(EXTRA_CATVOD_PID, 0) ?: 0
                } else {
                    0
                }
            }
        }

        val active = sandboxPids.isNotEmpty() || catVodActive
        if (!active) {
            clearState()
            stopForegroundAndSelf()
            return START_NOT_STICKY
        }

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(nm)

        val builder: Notification.Builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val contentPi = buildContentPendingIntent()
        val stopAllPi = PendingIntent.getService(
            this,
            1,
            Intent(this, ServiceHostService::class.java).setAction(ACTION_STOP_ALL),
            pendingFlags()
        )

        builder
            .setContentTitle(buildTitle())
            .setContentText(buildContentText())
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(contentPi)
            .addAction(0, "全部停止", stopAllPi)

        val gwUrl = gateway
        if (!gwUrl.isNullOrEmpty()) {
            builder.setStyle(Notification.BigTextStyle().bigText("网关运行中：$gwUrl"))
            val copyPi = PendingIntent.getService(
                this,
                2,
                Intent(this, ServiceHostService::class.java)
                    .setAction(ACTION_COPY_GW)
                    .putExtra(EXTRA_URL, gwUrl),
                pendingFlags()
            )
            builder.addAction(
                Notification.Action.Builder(R.drawable.ic_copy, "复制地址", copyPi).build()
            )
        }

        startForeground(NOTIFICATION_ID, builder.build())
        return START_STICKY
    }

    private fun buildTitle(): String {
        val parts = mutableListOf<String>()
        if (catVodActive) parts.add("猫影视 Node")
        if (sandboxPids.isNotEmpty()) {
            parts.add(
                if (sandboxServices >= 0 && sandboxPlugins >= 0) {
                    "插件 $sandboxPlugins · 服务 $sandboxServices"
                } else {
                    "${sandboxPids.size} 个服务"
                }
            )
        }
        return "源影运行中" + if (parts.isEmpty()) "" else " · ${parts.joinToString(" · ")}"
    }

    private fun buildContentText(): String {
        val gw = gateway
        if (!gw.isNullOrEmpty()) return "网关运行中：$gw"
        if (catVodActive) {
            return if (catVodPid > 0) {
                "猫影视 Node 在后台持续运行，点按管理"
            } else {
                "猫影视 Node 正在启动或重启，点按管理"
            }
        }
        return "服务在后台持续运行，点按管理"
    }

    private fun stopPids(pids: IntArray) {
        if (pids.isEmpty()) return
        Thread {
            pids.forEach { pid ->
                try {
                    val process = Runtime.getRuntime().exec(arrayOf("kill", "-TERM", "$pid"))
                    process.waitFor()
                } catch (_: Throwable) {
                }
            }
            try {
                Thread.sleep(2000)
            } catch (_: Throwable) {
            }
            pids.forEach { pid ->
                try {
                    if (isProcessAlive(pid)) {
                        Process.killProcess(pid)
                    }
                } catch (_: Throwable) {
                }
            }
        }.start()
    }

    private fun stopForegroundAndSelf() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
            @Suppress("DEPRECATION")
            try {
                stopForeground(true)
            } catch (_: Throwable) {
            }
        }
        stopSelf()
    }

    private fun buildContentPendingIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        return if (launch != null) {
            PendingIntent.getActivity(this, 0, launch, pendingFlags())
        } else {
            PendingIntent.getActivity(
                this,
                0,
                Intent(Intent.ACTION_MAIN).setPackage(packageName),
                pendingFlags()
            )
        }
    }

    private fun ensureChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "服务运行",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "沙盒与猫影视 Node 运行状态"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun pendingFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }
}
