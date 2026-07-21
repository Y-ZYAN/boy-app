package com.momapp.boy_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val CHANNEL = "usage_stats"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "hasUsageStatsPermission" -> {
                            result.success(checkUsageStatsPermission())
                        }
                        "openUsageStatsSettings" -> {
                            openUsageStatsSettings()
                            result.success(true)
                        }
                        "queryUsageSessions" -> {
                            querySessionsAsync(result)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            }
    }

    // ─── 工具方法 ────────────────────────────────────────────────────────

    private fun checkUsageStatsPermission(): Boolean {
        val appOps = getSystemService(APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOp(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageStatsSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    // ─── 会话数据结构 ──────────────────────────────────────────────────

    data class Session(
        val packageName: String,
        val appName: String,
        val startTimeMillis: Long,
        val endTimeMillis: Long,   // -1 表示正在使用
        val isUninstalled: Boolean = false
    )

    // ─── 查询使用会话（后台线程） ──────────────────────────────────────

    private val mainHandler = Handler(Looper.getMainLooper())

    private fun querySessionsAsync(channelResult: MethodChannel.Result) {
        Thread {
            try {
                val data = buildSessionResult()
                mainHandler.post { channelResult.success(data) }
            } catch (e: Exception) {
                mainHandler.post { channelResult.error("QUERY_FAILED", e.message, null) }
            }
        }.start()
    }

    /** 获取今天 00:00 到现在的毫秒时间戳对 */
    private fun getTodayRange(): Pair<Long, Long> {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return Pair(cal.timeInMillis, System.currentTimeMillis())
    }

    /** 配对会话 + 息屏统计（单次事件遍历完成两件事） */
    private data class PairingResult(
        val sessions: List<Session>,
        val screenOffMs: Long
    )

    private fun pairSessions(events: UsageEvents, now: Long): PairingResult {
        val result = mutableListOf<Session>()
        var currentPkg: String? = null
        var currentStart: Long = 0
        var screenOffStart: Long = -1
        var screenOffMs: Long = 0

        fun closeSession(endTime: Long) {
            val pkg = currentPkg ?: return
            val appName = resolveAppName(pkg)
            val uninstalled = appName == pkg
            result.add(
                Session(
                    packageName = pkg,
                    appName = appName,
                    startTimeMillis = currentStart,
                    endTimeMillis = endTime,
                    isUninstalled = uninstalled
                )
            )
            currentPkg = null
        }

        while (events.hasNextEvent()) {
            val e = UsageEvents.Event()
            events.getNextEvent(e)

            when (e.eventType) {
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    screenOffStart = e.timeStamp
                }
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    if (screenOffStart > 0) {
                        screenOffMs += e.timeStamp - screenOffStart
                        screenOffStart = -1
                    }
                }
            }

            val pkg = e.packageName ?: continue
            when (e.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND,
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    if (currentPkg != null && currentPkg != pkg) closeSession(e.timeStamp)
                    if (currentPkg == null) {
                        currentPkg = pkg
                        currentStart = e.timeStamp
                    }
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND,
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    if (currentPkg == pkg) closeSession(e.timeStamp)
                }
            }
        }

        // 屏幕仍处于息屏状态
        if (screenOffStart > 0) screenOffMs += now - screenOffStart
        // 仍在使用的 App
        if (currentPkg != null) closeSession(now)

        return PairingResult(result, screenOffMs)
    }

    /** 计算所有会话的原始总时长（含短会话） */
    private fun computeTotalMillis(sessions: List<Session>, now: Long): Long {
        return sessions.sumOf {
            if (it.endTimeMillis == -1L) now - it.startTimeMillis
            else it.endTimeMillis - it.startTimeMillis
        }
    }

    companion object {
        private const val MIN_SESSION_MS = 60_000L
    }

    /** 过滤短会话，附图标数据 */
    private fun filterAndPrepareResult(
        sessions: List<Session>,
        now: Long,
        screenOffMs: Long,
        totalRecordedMs: Long
    ): Map<String, Any?> {
        val iconCache = mutableMapOf<String, ByteArray>()
        val uninstalledSeen = mutableSetOf<String>()

        val filtered = sessions
            .filter { it.endTimeMillis - it.startTimeMillis >= MIN_SESSION_MS || it.endTimeMillis == -1L }
            .map { s ->
                if (s.packageName !in iconCache && s.packageName !in uninstalledSeen) {
                    if (!s.isUninstalled) {
                        getAppIconBytes(s.packageName)?.let { iconCache[s.packageName] = it }
                    } else {
                        uninstalledSeen.add(s.packageName)
                    }
                }
                mapOf(
                    "packageName" to s.packageName,
                    "appName" to s.appName,
                    "startTimeMillis" to s.startTimeMillis,
                    "endTimeMillis" to if (s.endTimeMillis == -1L) -1L else s.endTimeMillis,
                    "isUninstalled" to s.isUninstalled
                )
            }

        return mapOf(
            "sessions" to filtered,
            "icons" to iconCache,
            "screenOffMillis" to screenOffMs,
            "totalRecordedMillis" to totalRecordedMs
        )
    }

    /** 主流程流水线 */
    private fun buildSessionResult(): Map<String, Any?> {
        val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        val (todayStart, now) = getTodayRange()
        val events = usm.queryEvents(todayStart, now)
        val (pairedSessions, screenOffMs) = pairSessions(events, now)
        val totalRecordedMs = computeTotalMillis(pairedSessions, now)
        return filterAndPrepareResult(pairedSessions, now, screenOffMs, totalRecordedMs)
    }

    // ─── App 信息查询 ──────────────────────────────────────────────────

    /** 从 PackageManager 获取 App 的中文名；失败则回退到包名 */
    private fun resolveAppName(packageName: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }
    }

    /** 获取 App 图标 as PNG byte array；失败返回 null */
    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = if (drawable is BitmapDrawable) {
                drawable.bitmap
            } else {
                val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, 96, 96)
                drawable.draw(canvas)
                bmp
            }
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (_: Exception) {
            null
        }
    }
}
