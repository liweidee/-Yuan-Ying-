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
 * 服务托管前台服务
 *
 * 关键设计：
 *  - "全部停止"优先发 SIGTERM（proot --kill-on-exit 依赖此信号优雅退出）
 *  - 2 秒后仍有存活 → SIGKILL 兜底（避免漏子进程）
 *  - 通知栏文案与 PID 数量实时同步
 */
class ServiceHostService : Service() {

    companion object {
        const val ACTION_STOP_ALL = "com.example.yuanying.services.STOP_ALL"
        const val ACTION_COPY_GW = "com.example.yuanying.services.COPY_GW"

        const val EXTRA_PIDS = "pids"
        const val EXTRA_COUNT = "count"
        const val EXTRA_SERVICES = "services"
        const val EXTRA_PLUGINS = "plugins"
        const val EXTRA_GW = "gw"
        const val EXTRA_URL = "url"

        private const val CHANNEL_ID = "service_host"
        private const val NOTIFICATION_ID = 0x5948

        @Volatile
        private var pids: Array<Int> = emptyArray()

        private fun isProcessAlive(pid: Int): Boolean {
            return try {
                File("/proc/$pid").exists()
            } catch (_: Throwable) {
                false
            }
        }
    }

    private var gateway: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        // 分支 1：全部停止
        if (ACTION_STOP_ALL == action) {
            val captured = pids.copyOf()
            pids = emptyArray()

            // SIGTERM 优先，2 秒后 SIGKILL 兜底
            Thread {
                // 1. 先 SIGTERM（proot --kill-on-exit 会优雅退出并杀掉沙盒内子进程）
                captured.forEach { pid ->
                    try {
                        val p = Runtime.getRuntime().exec(arrayOf("kill", "-TERM", "$pid"))
                        p.waitFor()
                    } catch (_: Throwable) {}
                }
                // 2. 等 2 秒让 SIGTERM 生效
                try { Thread.sleep(2000) } catch (_: Throwable) {}
                // 3. 仍存活 → SIGKILL 兜底
                captured.forEach { pid ->
                    try {
                        if (isProcessAlive(pid)) {
                            Process.killProcess(pid)
                        }
                    } catch (_: Throwable) {}
                }
            }.start()

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
            } catch (_: Throwable) {
                @Suppress("DEPRECATION")
                try { stopForeground(true) } catch (_: Throwable) {}
            }
            stopSelf()
            return START_NOT_STICKY
        }

        // 分支 2：复制网关地址
        if (ACTION_COPY_GW == action) {
            val url = intent?.getStringExtra(EXTRA_URL)
            if (!url.isNullOrEmpty()) {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("gateway", url))
                Toast.makeText(applicationContext, "已复制 $url", Toast.LENGTH_SHORT).show()
            }
            return START_STICKY
        }

        // 分支 3：更新通知 + PID 列表
        val count = intent?.getIntExtra(EXTRA_COUNT, 0) ?: 0
        val services = intent?.getIntExtra(EXTRA_SERVICES, -1) ?: -1
        val plugins = intent?.getIntExtra(EXTRA_PLUGINS, -1) ?: -1
        val gw = intent?.getStringExtra(EXTRA_GW)
        gateway = if (!gw.isNullOrEmpty()) gw else null

        val list = intent?.getIntegerArrayListExtra(EXTRA_PIDS)
        pids = list?.toTypedArray() ?: emptyArray()

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
            this, 1,
            Intent(this, ServiceHostService::class.java).setAction(ACTION_STOP_ALL),
            pendingFlags()
        )

        val title = if (services < 0 || plugins < 0) {
            "源影服务运行中 · $count 个"
        } else {
            "源影运行中 · 插件 $plugins · 服务 $services"
        }

        builder
            .setContentTitle(title)
            .setContentText(gateway?.let { "网关运行中：$it" } ?: "服务在后台持续运行，点按管理")
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(contentPi)
            .addAction(0, "全部停止", stopAllPi)

        val gwUrl = gateway
        if (!gwUrl.isNullOrEmpty()) {
            builder.setStyle(Notification.BigTextStyle().bigText("网关运行中：$gwUrl"))
            val copyPi = PendingIntent.getService(
                this, 2,
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

    private fun buildContentPendingIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        return if (launch != null) {
            PendingIntent.getActivity(this, 0, launch, pendingFlags())
        } else {
            PendingIntent.getActivity(
                this, 0,
                Intent(Intent.ACTION_MAIN).setPackage(packageName),
                pendingFlags()
            )
        }
    }

    private fun ensureChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "服务运行",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "沙盒/插件服务运行状态"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(ch)
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