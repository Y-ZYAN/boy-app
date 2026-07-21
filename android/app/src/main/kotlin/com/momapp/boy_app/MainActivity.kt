package com.momapp.boy_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "usage_stats"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageStatsPermission" -> {
                    result.success(checkUsageStatsPermission())
                }
                "openUsageStatsSettings" -> {
                    openUsageStatsSettings()
                    result.success(true)
                }
                "queryUsageSessions" -> {
                    val sessions = queryUsageSessions()
                    result.success(sessions)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

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

    // ─── 查询使用会话 ────────────────────────────────────────────────

    data class Session(
        val packageName: String,
        val appName: String,
        val startTimeMillis: Long,
        val endTimeMillis: Long   // -1 表示正在使用
    )

    private fun queryUsageSessions(): List<Map<String, Any?>> {
        val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager

        // 今天 00:00 → 现在
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val todayStart = cal.timeInMillis
        val now = System.currentTimeMillis()

        val sessions = mutableListOf<Session>()
        val events = usm.queryEvents(todayStart, now)

        var currentPkg: String? = null
        var currentStart: Long = 0

        fun closeSession(endTime: Long) {
            val pkg = currentPkg ?: return
            sessions.add(
                Session(
                    packageName = pkg,
                    appName = resolveAppName(pkg),
                    startTimeMillis = currentStart,
                    endTimeMillis = endTime
                )
            )
            currentPkg = null
        }

        while (events.hasNextEvent()) {
            val e = UsageEvents.Event()
            events.getNextEvent(e)

            val pkg = e.packageName ?: continue
            val time = e.timeStamp
            val eventType = e.eventType

            when (eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND,
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    // 切到另一个 App → 关掉前一个会话
                    if (currentPkg != null && currentPkg != pkg) {
                        closeSession(time)
                    }
                    if (currentPkg == null) {
                        currentPkg = pkg
                        currentStart = time
                    }
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND,
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    if (currentPkg == pkg) {
                        closeSession(time)
                    }
                }
            }
        }

        // 仍在使用的 App → 结束时间设为 now
        if (currentPkg != null) {
            closeSession(now)
        }

        // 序列化为 Flutter 可用的 List<Map>
        return sessions.map { s ->
            mapOf(
                "packageName" to s.packageName,
                "appName" to s.appName,
                "startTimeMillis" to s.startTimeMillis,
                "endTimeMillis" to if (s.endTimeMillis == -1L) -1L else s.endTimeMillis
            )
        }
    }

    /** 从 PackageManager 获取 App 的中文名；失败则回退到包名 */
    private fun resolveAppName(packageName: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }
    }
}
