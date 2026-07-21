import 'package:flutter/material.dart';

import '../models/app_usage_session.dart';
import '../services/usage_stats_service.dart';
import '../utils/format_utils.dart';
import 'app_icon.dart';

/// 近期使用 Tab：按时间线展示最近打开的 App
class RecentTab extends StatelessWidget {
  final QueryResult data;
  final Future<void> Function() onRefresh;

  const RecentTab({
    super.key,
    required this.data,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = List<AppUsageSession>.from(data.sessions)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final s = sorted[index];
          // 用 divider 分隔不同的 App
          final prevPkg =
              index < sorted.length - 1 ? sorted[index + 1].appName : null;
          final showDivider = prevPkg != null && prevPkg != s.appName;

          return Column(
            children: [
              if (showDivider) _buildDivider(context),
              _buildRecentRow(context, s),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child:
                Icon(Icons.swap_vert, size: 16, color: Colors.grey[400]),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildRecentRow(BuildContext context, AppUsageSession s) {
    final color = s.isActive ? Colors.green : Colors.grey;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: AppIcon(
          appName: s.appName,
          packageName: s.packageName,
          icons: data.icons,
          active: s.isActive,
        ),
        title: Text(
          _sessionTitle(s.appName, s.isUninstalled),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(formatTimeRange(s.startTime, s.endTime)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatDuration(s.duration),
              style: TextStyle(fontWeight: FontWeight.w500, color: color[700]),
            ),
            if (s.isActive)
              Text('使用中',
                  style:
                      TextStyle(color: Colors.green[600], fontSize: 11)),
          ],
        ),
      ),
    );
  }

  String _sessionTitle(String appName, bool uninstalled) {
    return uninstalled ? '$appName (已卸载)' : appName;
  }
}
