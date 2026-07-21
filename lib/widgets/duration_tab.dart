import 'dart:math';
import 'package:flutter/material.dart';

import '../models/app_usage_session.dart';
import '../services/usage_stats_service.dart';
import '../utils/format_utils.dart';
import 'app_icon.dart';

/// 时长排序 Tab：今日总览 + 按 App 汇总时长
class DurationTab extends StatelessWidget {
  final QueryResult data;
  final Future<void> Function() onRefresh;

  const DurationTab({
    super.key,
    required this.data,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByApp(data.sessions);
    final sorted = _sortByDurationDesc(grouped);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(context),
          const SizedBox(height: 8),
          for (final entry in sorted)
            _buildAppGroupCard(context, entry.key, entry.value),
        ],
      ),
    );
  }

  // ─── 分组排序 ───────────────────────────────────────────────────────

  Map<String, List<AppUsageSession>> _groupByApp(List<AppUsageSession> sessions) {
    final grouped = <String, List<AppUsageSession>>{};
    for (final s in sessions) {
      grouped.putIfAbsent(s.appName, () => []).add(s);
    }
    return grouped;
  }

  List<MapEntry<String, List<AppUsageSession>>> _sortByDurationDesc(
      Map<String, List<AppUsageSession>> grouped) {
    final sorted = grouped.entries.toList()
      ..sort((a, b) {
        final da = a.value
            .fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
        final db = b.value
            .fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
        return db.compareTo(da);
      });
    return sorted;
  }

  // ─── 今日总览卡片 ───────────────────────────────────────────────────

  Widget _buildSummaryCard(BuildContext context) {
    final totalDuration = Duration(seconds: data.totalRecordedSeconds);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('今日屏幕使用时间',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              formatDuration(totalDuration),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            _buildTimeBreakdown(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBreakdown(BuildContext context) {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final elapsedSeconds = now.difference(midnight).inSeconds;
    final otherSeconds =
        max(0, elapsedSeconds - data.totalRecordedSeconds - data.screenOffSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '息屏 ${formatDuration(Duration(seconds: data.screenOffSeconds))}',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
        if (otherSeconds > 60)
          Text(
            '其他 ${formatDuration(Duration(seconds: otherSeconds))}',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
      ],
    );
  }

  // ─── App 分组卡片 ───────────────────────────────────────────────────

  Widget _buildAppGroupCard(
      BuildContext context, String appName, List<AppUsageSession> sessions) {
    final total =
        sessions.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
    sessions.sort((a, b) => a.startTime.compareTo(b.startTime));
    final pkg = sessions.first.packageName;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: AppIcon(
          appName: appName,
          packageName: pkg,
          icons: data.icons,
        ),
        title: Text(
          _sessionTitle(appName, sessions.first.isUninstalled),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '总计 ${formatDuration(total)}',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children:
                  sessions.map((s) => _buildSessionRow(context, s)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(BuildContext context, AppUsageSession s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            formatTimeRange(s.startTime, s.endTime),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 8),
          if (s.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('使用中',
                  style: TextStyle(color: Colors.green, fontSize: 11)),
            ),
          const Spacer(),
          Text(
            formatDuration(s.duration),
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _sessionTitle(String appName, bool uninstalled) {
    return uninstalled ? '$appName (已卸载)' : appName;
  }
}
