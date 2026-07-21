package com.momapp.boy_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Build
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // ── Phase 1: 权限 + 查询 ────────────────────────────
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
                // ── Phase 2: 限额管理 ────────────────────────────────
                "startMonitoring" -> {
                    val granted = checkOverlayPermission()
                    if (granted) {
                        val intent = Intent(this, EnforcementService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "stopMonitoring" -> {
                    stopService(Intent(this, EnforcementService::class.java))
                    result.success(true)
                }
                "isMonitoringActive" -> {
                    result.success(EnforcementService.isRunning)
                }
                "checkOverlayPermission" -> {
                    result.success(checkOverlayPermission())
                }
                "openOverlaySettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                    startActivity(intent)
                    result.success(true)
                }
                "setAppLimit" -> {
                    val pkg = call.argument<String>("packageName")
                    val minutes = call.argument<Int>("dailyMinutes") ?: 0
                    if (pkg != null && minutes > 0) {
                        UsageLimitManager.setLimit(this, pkg, minutes)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "packageName or dailyMinutes missing", null)
                    }
                }
                "removeAppLimit" -> {
                    val pkg = call.argument<String>("packageName")
                    if (pkg != null) {
                        UsageLimitManager.removeLimit(this, pkg)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "packageName missing", null)
                    }
                }
                "getAppLimits" -> {
                    val limits = UsageLimitManager.getAllLimits(this)
                    val list = limits.map { mapOf(
                        "packageName" to it.packageName,
                        "dailyMinutes" to it.dailyMinutes
                    ) }
                    result.success(list)
                }
                "getAppDailyUsage" -> {
                    val pkg = call.argument<String>("packageName")
                    if (pkg != null) {
                        val seconds = UsageLimitManager.getDailyUsageSeconds(this, pkg)
                        result.success(seconds)
                    } else {
                        result.error("INVALID_ARGS", "packageName missing", null)
                    }
                }
                "getInstalledApps" -> {
                    val list = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
                        .filter { info ->
                            // 只保留有桌面图标的 App（排除系统服务）
                            packageManager.getLaunchIntentForPackage(info.packageName) != null
                        }
                        .filter { it.packageName != packageName } // 排除自己
                        .map { info ->
                            mapOf(
                                "packageName" to info.packageName,
                                "appName" to (packageManager.getApplicationLabel(info)?.toString() ?: info.packageName)
                            )
                        }
                    result.success(list)
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

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else true
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

    private fun queryUsageSessions(): Map<String, Any?> {
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

        // 仍在使用的 App
        if (currentPkg != null) {
            closeSession(now)
        }

        // ── 过滤短会话 + 收集图标 ────────────────────────────────────
        val MIN_SESSION_MS = 60_000L  // < 1 分钟的丢掉
        val iconCache = mutableMapOf<String, ByteArray>()

        val filteredSessions = sessions
            .filter { it.endTimeMillis - it.startTimeMillis >= MIN_SESSION_MS || it.endTimeMillis == -1L }
            .map { s ->
                // 首次出现的包名才去拿图标
                if (s.packageName !in iconCache) {
                    getAppIconBytes(s.packageName)?.let { iconCache[s.packageName] = it }
                }
                mapOf(
                    "packageName" to s.packageName,
                    "appName" to s.appName,
                    "startTimeMillis" to s.startTimeMillis,
                    "endTimeMillis" to if (s.endTimeMillis == -1L) -1L else s.endTimeMillis
                )
            }

        // icons: Map<String, ByteArray> → Flutter 收到 Map<String, Uint8List>
        return mapOf(
            "sessions" to filteredSessions,
            "icons" to iconCache
        )
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

    /** 获取 App 图标 as PNG byte array；失败返回 null */
    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = if (drawable is BitmapDrawable) {
                drawable.bitmap
            } else {
                // VectorDrawable 等 → 画到固定尺寸 Bitmap 上
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
