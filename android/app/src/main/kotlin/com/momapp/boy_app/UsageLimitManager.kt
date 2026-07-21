package com.momapp.boy_app

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * App 使用限额管理器。
 *
 * 职责：
 * 1. 存储/读取 App 每日限额（SharedPreferences JSON）
 * 2. 通过 UsageStatsManager.queryEvents 计算 App 今日已用时间
 */
object UsageLimitManager {

    private const val PREFS_NAME = "boy_app_limits"
    private const val LIMITS_JSON_KEY = "limits"

    /**
     * 单个 App 的限额配置
     * @property dailyMinutes 每日允许使用分钟数（> 0 有效）
     */
    data class AppLimitConfig(
        val packageName: String,
        val dailyMinutes: Int
    )

    // ─── 限额持久化 ─────────────────────────────────────────────────

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 设置 App 每日限额（分钟） */
    fun setLimit(context: Context, packageName: String, dailyMinutes: Int) {
        val map = loadAll(prefs(context)).toMutableMap()
        map[packageName] = dailyMinutes
        saveAll(prefs(context), map)
    }

    /** 删除 App 限额 */
    fun removeLimit(context: Context, packageName: String) {
        val map = loadAll(prefs(context)).toMutableMap()
        map.remove(packageName)
        saveAll(prefs(context), map)
    }

    /** 查询单个 App 限额 */
    fun getLimit(context: Context, packageName: String): AppLimitConfig? {
        val mins = loadAll(prefs(context))[packageName] ?: return null
        return AppLimitConfig(packageName, mins)
    }

    /** 查询所有已设限额 */
    fun getAllLimits(context: Context): List<AppLimitConfig> {
        return loadAll(prefs(context)).map { (pkg, min) ->
            AppLimitConfig(pkg, min)
        }
    }

    /** 清空全部限额 */
    fun clearAllLimits(context: Context) {
        prefs(context).edit().remove(LIMITS_JSON_KEY).apply()
    }

    /** 加载全部限额（packageName → dailyMinutes） */
    private fun loadAll(prefs: SharedPreferences): Map<String, Int> {
        val json = prefs.getString(LIMITS_JSON_KEY, null) ?: return emptyMap()
        return try {
            val arr = JSONArray(json)
            val map = mutableMapOf<String, Int>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                map[obj.getString("packageName")] = obj.getInt("dailyMinutes")
            }
            map
        } catch (_: Exception) {
            emptyMap()
        }
    }

    /** 保存全部限额 */
    private fun saveAll(prefs: SharedPreferences, limits: Map<String, Int>) {
        val arr = JSONArray()
        limits.forEach { (pkg, min) ->
            arr.put(JSONObject().apply {
                put("packageName", pkg)
                put("dailyMinutes", min)
            })
        }
        prefs.edit().putString(LIMITS_JSON_KEY, arr.toString()).apply()
    }

    // ─── 使用量计算 ─────────────────────────────────────────────────

    /**
     * 计算 App 今天的已用前台时间（秒）。
     * 使用 queryEvents 逐事件配对，比 queryAndAggregateUsageStats 更实时。
     */
    fun getDailyUsageSeconds(context: Context, packageName: String): Int {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startOfDay = cal.timeInMillis
        val now = System.currentTimeMillis()

        var totalMs = 0L
        var sessionStart = -1L

        try {
            val events = usm.queryEvents(startOfDay, now)
            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (packageName != event.packageName) continue
                when (event.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND,
                    UsageEvents.Event.ACTIVITY_RESUMED -> {
                        sessionStart = event.timeStamp
                    }
                    UsageEvents.Event.MOVE_TO_BACKGROUND,
                    UsageEvents.Event.ACTIVITY_PAUSED -> {
                        if (sessionStart >= 0) {
                            totalMs += event.timeStamp - sessionStart
                            sessionStart = -1
                        }
                    }
                }
            }
            // 若仍在前台，累加到当前时刻
            if (sessionStart >= 0) totalMs += now - sessionStart
        } catch (_: Exception) {}

        return (totalMs / 1000).toInt()
    }

    /** 检查 App 是否已超限，未设限额返回 false */
    fun isOverLimit(context: Context, packageName: String): Boolean {
        val limit = getLimit(context, packageName) ?: return false
        val usedSeconds = getDailyUsageSeconds(context, packageName)
        return usedSeconds >= limit.dailyMinutes * 60
    }
}
