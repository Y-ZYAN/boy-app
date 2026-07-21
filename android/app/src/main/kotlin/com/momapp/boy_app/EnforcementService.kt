package com.momapp.boy_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.util.Calendar
import kotlin.jvm.Volatile

/**
 * 前台服务：持续监控当前前台 App，检查使用限额，超限时弹出遮挡悬浮窗。
 *
 * 工作方式：
 * 1. 每 5 秒通过 UsageStatsManager.queryEvents 检测当前前台 App
 * 2. 对比 UsageLimitManager 中的限额配置
 * 3. 超限 → TYPE_APPLICATION_OVERLAY 全屏遮挡
 * 4. 用户按"关闭"回到桌面
 */
class EnforcementService : Service() {

    companion object {
        private const val CHANNEL_ID = "boy_app_enforcement"
        private const val NOTIFICATION_ID = 1001
        private const val POLL_INTERVAL_MS = 5000L

        @Volatile
        var isRunning = false
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var screenInteractive = true
    private var screenStateReceiver: BroadcastReceiver? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        registerScreenStateReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        isRunning = true
        handler.post(enforcementLoop)
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(enforcementLoop)
        dismissOverlay()
        unregisterScreenStateReceiver()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ─── 轮询 ────────────────────────────────────────────────────────

    private val enforcementLoop = object : Runnable {
        override fun run() {
            try {
                if (screenInteractive) {
                    val foregroundPkg = detectForegroundApp()
                    if (foregroundPkg != null) {
                        enforcePackage(foregroundPkg)
                    }
                }
            } catch (_: Exception) {
            } finally {
                handler.postDelayed(this, POLL_INTERVAL_MS)
            }
        }
    }

    /**
     * 通过 UsageStatsManager.queryEvents 检测当前前台 App。
     * 原理：从今天 00:00 起扫描所有事件，跟踪未配对的 FOREGROUND→BACKGROUND。
     * 若某 App 有 FOREGROUND 但尚未收到 BACKGROUND，即为当前前台。
     * 多个未配对时取时间戳最新的（最后切到前台的）。
     */
    private fun detectForegroundApp(): String? {
        val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val todayStart = cal.timeInMillis
        val now = System.currentTimeMillis()

        val openSessions = mutableMapOf<String, Long>()
        val events = usm.queryEvents(todayStart, now)

        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND,
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    openSessions[pkg] = event.timeStamp
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND,
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    openSessions.remove(pkg)
                }
            }
        }

        if (openSessions.isNotEmpty()) {
            return openSessions.maxByOrNull { it.value }?.key
        }
        return null
    }

    /**
     * 检查指定 App 是否超限，超限则弹出遮挡层。
     */
    private fun enforcePackage(pkg: String) {
        // 不封锁自己
        if (pkg == packageName) return

        val limit = UsageLimitManager.getLimit(this, pkg) ?: return
        val usedSeconds = UsageLimitManager.getDailyUsageSeconds(this, pkg)
        val limitSeconds = limit.dailyMinutes * 60

        if (usedSeconds >= limitSeconds) {
            val appName = resolveAppName(pkg)
            showOverlay(pkg, appName, "今日限额已用完（${limit.dailyMinutes} 分钟）")
        } else {
            // 不再超限则收起遮挡（比如用户调整了限额）
            if (overlayView != null && pkg == overlayPkg) {
                dismissOverlay()
            }
        }
    }

    private var overlayPkg: String? = null

    private fun resolveAppName(pkg: String): String {
        return try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            pkg
        }
    }

    // ─── 悬浮窗遮挡 ──────────────────────────────────────────────────

    private fun showOverlay(pkg: String, appName: String, reason: String) {
        if (overlayView != null) return
        if (!screenInteractive) return
        // 没有悬浮窗权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) return

        // 构建全屏遮挡布局
        val layout = FrameLayout(this).apply {
            setBackgroundColor(Color.argb(220, 0, 0, 0))
        }

        val contentView = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).also { it.gravity = Gravity.CENTER }
        }

        // 深色背景卡片
        val card = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(48, 48, 48, 48)
            setBackgroundColor(Color.argb(200, 30, 30, 30))
        }

        card.addView(TextView(this).apply {
            text = "⏰ $appName"
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity = Gravity.CENTER
        })
        card.addView(android.widget.Space(this).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(0, 32)
        })
        card.addView(TextView(this).apply {
            text = reason
            setTextColor(Color.parseColor("#FFCCCC"))
            textSize = 16f
            gravity = Gravity.CENTER
        })
        card.addView(android.widget.Space(this).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(0, 48)
        })
        card.addView(Button(this).apply {
            text = "我知道了，回桌面"
            setOnClickListener { goToHomeScreen() }
        })

        contentView.addView(card)
        layout.addView(contentView)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_SYSTEM_ALERT,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )

        try {
            windowManager.addView(layout, params)
            overlayView = layout
            overlayPkg = pkg
        } catch (_: Exception) {
            overlayView = null
            overlayPkg = null
        }
    }

    private fun dismissOverlay() {
        overlayView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
            overlayView = null
            overlayPkg = null
        }
    }

    private fun goToHomeScreen() {
        dismissOverlay()
        Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }.also { startActivity(it) }
    }

    // ─── 屏幕状态监听 ────────────────────────────────────────────────

    private fun registerScreenStateReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        screenStateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        screenInteractive = false
                        handler.post { dismissOverlay() }
                    }
                    Intent.ACTION_SCREEN_ON -> {
                        screenInteractive = true
                    }
                }
            }
        }
        registerReceiver(screenStateReceiver, filter)
    }

    private fun unregisterScreenStateReceiver() {
        screenStateReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
            screenStateReceiver = null
        }
    }

    // ─── 前台通知 ────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel(
                CHANNEL_ID,
                "手机守护监控中",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "后台监控 App 使用时长"
                val nm = getSystemService(NotificationManager::class.java)
                nm.createNotificationChannel(this)
            }
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("手机守护监控中")
            .setContentText("正在监控 App 使用时长")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }
}
