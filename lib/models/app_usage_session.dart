import 'dart:typed_data';

/// 一次 App 使用会话（从打开到关闭/切到后台）
class AppUsageSession {
  final String packageName;
  final String appName;
  final DateTime startTime;
  final DateTime? endTime; // null = 正在使用

  AppUsageSession({
    required this.packageName,
    required this.appName,
    required this.startTime,
    this.endTime,
  });

  factory AppUsageSession.fromMap(Map<String, dynamic> map) {
    final endMs = map['endTimeMillis'] as int;
    return AppUsageSession(
      packageName: map['packageName'] as String,
      appName: map['appName'] as String,
      startTime:
          DateTime.fromMillisecondsSinceEpoch(map['startTimeMillis'] as int),
      endTime: endMs == -1 ? null : DateTime.fromMillisecondsSinceEpoch(endMs),
    );
  }

  Duration get duration =>
      endTime != null
          ? endTime!.difference(startTime)
          : DateTime.now().difference(startTime);

  bool get isActive => endTime == null;
}

/// App 限额配置
class AppLimit {
  final String packageName;
  final String appName;
  final int dailyMinutes; // 每日限额（分钟），0 表示不限
  final String? scheduleStart; // 可用时段开始 "HH:mm"
  final String? scheduleEnd; // 可用时段结束 "HH:mm"

  AppLimit({
    required this.packageName,
    required this.appName,
    required this.dailyMinutes,
    this.scheduleStart,
    this.scheduleEnd,
  });

  factory AppLimit.fromJson(Map<String, dynamic> json) => AppLimit(
        packageName: json['packageName'] as String,
        appName: json['appName'] as String,
        dailyMinutes: json['dailyMinutes'] as int,
        scheduleStart: json['scheduleStart'] as String?,
        scheduleEnd: json['scheduleEnd'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'appName': appName,
        'dailyMinutes': dailyMinutes,
        if (scheduleStart != null) 'scheduleStart': scheduleStart,
        if (scheduleEnd != null) 'scheduleEnd': scheduleEnd,
      };
}

/// App 图标缓存（包名 → PNG 字节数组）
typedef IconCache = Map<String, Uint8List?>;
