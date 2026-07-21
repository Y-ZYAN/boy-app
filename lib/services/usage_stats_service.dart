import 'package:flutter/services.dart';

import '../widgets/app_icon.dart';
import '../models/app_usage_session.dart';

/// MethodChannel 封装，所有原生调用走这里
class UsageStatsService {
  static const _channel = MethodChannel('usage_stats');

  static final UsageStatsService _instance = UsageStatsService._();
  factory UsageStatsService() => _instance;
  UsageStatsService._();

  Future<bool> hasPermission() async {
    final result = await _channel.invokeMethod<bool>('hasUsageStatsPermission');
    return result ?? false;
  }

  Future<void> openSettings() async {
    await _channel.invokeMethod('openUsageStatsSettings');
  }

  /// 查询使用数据，返回 (sessions, icons, screenOffSeconds, totalRecordedSeconds)
  Future<QueryResult> querySessions() async {
    final raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('queryUsageSessions');
    if (raw == null) throw Exception('查询数据失败');

    final rawSessions = raw['sessions'] as List<dynamic>;
    final rawIcons = raw['icons'] as Map<dynamic, dynamic>? ?? {};
    final screenOffMs = raw['screenOffMillis'] as int? ?? 0;
    final totalRecordedMs = raw['totalRecordedMillis'] as int? ?? 0;

    return QueryResult(
      sessions: rawSessions
          .cast<Map<dynamic, dynamic>>()
          .map((m) => AppUsageSession.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      icons: rawIcons
          .map((key, value) => MapEntry(key as String, value as Uint8List?)),
      screenOffSeconds: (screenOffMs / 1000).round(),
      totalRecordedSeconds: (totalRecordedMs / 1000).round(),
    );
  }
}

class QueryResult {
  final List<AppUsageSession> sessions;
  final IconCache icons;
  final int screenOffSeconds;
  final int totalRecordedSeconds;

  QueryResult({
    required this.sessions,
    required this.icons,
    required this.screenOffSeconds,
    required this.totalRecordedSeconds,
  });
}
