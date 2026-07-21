import 'package:flutter/services.dart';

/// Flutter 端封装：所有与原生 EnforcementService 通信的方法。
class EnforcementService {
  static const _channel = MethodChannel('usage_stats');

  // ── 前台监控 ─────────────────────────────────────────────────────

  /// 启动前台监控服务，返回是否成功（需先授予悬浮窗权限）
  static Future<bool> startMonitoring() async {
    final ok = await _channel.invokeMethod<bool>('startMonitoring');
    return ok ?? false;
  }

  /// 停止前台监控服务
  static Future<void> stopMonitoring() async {
    await _channel.invokeMethod('stopMonitoring');
  }

  /// 检查监控服务是否在运行
  static Future<bool> isMonitoringActive() async {
    final active = await _channel.invokeMethod<bool>('isMonitoringActive');
    return active ?? false;
  }

  // ── 悬浮窗权限 ───────────────────────────────────────────────────

  /// 检查是否已授予「在其他应用上层显示」权限
  static Future<bool> checkOverlayPermission() async {
    final ok = await _channel.invokeMethod<bool>('checkOverlayPermission');
    return ok ?? false;
  }

  /// 打开悬浮窗权限设置页
  static Future<void> openOverlaySettings() async {
    await _channel.invokeMethod('openOverlaySettings');
  }

  // ── 限额管理 ─────────────────────────────────────────────────────

  /// 设置 App 每日限额（分钟）
  static Future<void> setAppLimit(String packageName, int dailyMinutes) async {
    await _channel.invokeMethod('setAppLimit', {
      'packageName': packageName,
      'dailyMinutes': dailyMinutes,
    });
  }

  /// 删除 App 限额
  static Future<void> removeAppLimit(String packageName) async {
    await _channel.invokeMethod('removeAppLimit', {
      'packageName': packageName,
    });
  }

  /// 获取所有已设限额
  static Future<List<Map<String, dynamic>>> getAppLimits() async {
    final list = await _channel.invokeMethod<List<dynamic>>('getAppLimits');
    if (list == null) return [];
    return list.cast<Map<String, dynamic>>();
  }

  /// 查询指定 App 今日已用时长（秒）
  static Future<int> getAppDailyUsage(String packageName) async {
    final seconds = await _channel.invokeMethod<int>('getAppDailyUsage', {
      'packageName': packageName,
    });
    return seconds ?? 0;
  }

  /// 获取所有已安装 App（有桌面图标的）
  static Future<List<Map<String, dynamic>>> getInstalledApps() async {
    final list = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
    if (list == null) return [];
    return list.cast<Map<String, dynamic>>();
  }
}
