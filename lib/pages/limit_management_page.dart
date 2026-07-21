import 'package:flutter/material.dart';

import '../models/app_usage_session.dart';
import '../services/enforcement_service.dart';
import '../utils/format_utils.dart';

/// 限额管理 Tab：浏览已安装 App，设置/查看每日使用限额
class LimitManagementPage extends StatefulWidget {
  final List<AppUsageSession> todaySessions;
  final IconCache iconCache;

  const LimitManagementPage({
    super.key,
    required this.todaySessions,
    required this.iconCache,
  });

  @override
  State<LimitManagementPage> createState() => _LimitManagementPageState();
}

class _LimitManagementPageState extends State<LimitManagementPage> {
  // 合并：已安装 App + 已有限额 + 今日用量
  List<_AppLimitItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // 并行获取三个数据源，单个失败不影响其他
      final results = await Future.wait([
        EnforcementService.getInstalledApps().catchError((_) => <Map<String, dynamic>>[]),
        EnforcementService.getAppLimits().catchError((_) => <Map<String, dynamic>>[]),
        _computeUsageMap(),
      ]);

      final apps = results[0] as List<Map<String, dynamic>>;
      final limits = results[1] as List<Map<String, dynamic>>;
      final usageMap = results[2] as Map<String, int>;

      // 构建限额查找表
      final limitMap = <String, int>{};
      for (final l in limits) {
        limitMap[l['packageName'] as String] = l['dailyMinutes'] as int;
      }

      final items = apps.map((app) {
        final pkg = app['packageName'] as String;
        return _AppLimitItem(
          packageName: pkg,
          appName: app['appName'] as String,
          dailyMinutes: limitMap[pkg] ?? 0,
          usedSeconds: usageMap[pkg] ?? 0,
        );
      }).toList();

      // 有限额的排前面，按名称排序
      items.sort((a, b) {
        final aHas = a.dailyMinutes > 0 ? 0 : 1;
        final bHas = b.dailyMinutes > 0 ? 0 : 1;
        if (aHas != bHas) return aHas.compareTo(bHas);
        return a.appName.compareTo(b.appName);
      });

      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<Map<String, int>> _computeUsageMap() async {
    final map = <String, int>{};
    for (final s in widget.todaySessions) {
      if (!map.containsKey(s.packageName)) {
        map[s.packageName] = await EnforcementService.getAppDailyUsage(s.packageName);
      }
    }
    return map;
  }

  IconCache get _icons => widget.iconCache;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _items.length,
        itemBuilder: (context, index) => _buildRow(_items[index]),
      ),
    );
  }

  Widget _buildRow(_AppLimitItem item) {
    final hasLimit = item.dailyMinutes > 0;
    final limitSeconds = item.dailyMinutes * 60;
    final ratio = hasLimit && limitSeconds > 0
        ? (item.usedSeconds / limitSeconds).clamp(0.0, 1.0)
        : 0.0;
    final overLimit = hasLimit && item.usedSeconds >= limitSeconds;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showLimitDialog(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // App 图标
              _buildIcon(item),
              const SizedBox(width: 12),
              // 名称 + 限额信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.appName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    if (hasLimit) ...[
                      // 进度条
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation(
                            overLimit ? Colors.red : Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已用 ${formatDuration(Duration(seconds: item.usedSeconds))} / 限额 ${item.dailyMinutes} 分钟',
                        style: TextStyle(
                          fontSize: 12,
                          color: overLimit ? Colors.red[700] : Colors.grey[600],
                        ),
                      ),
                    ] else
                      Text('未设置限额',
                          style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(_AppLimitItem item) {
    final bytes = _icons[item.packageName];
    if (bytes != null && bytes.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: Image.memory(
            bytes,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackIcon(item.appName),
          ),
        ),
      );
    }
    return _fallbackIcon(item.appName);
  }

  Widget _fallbackIcon(String appName) {
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        appName.isNotEmpty ? appName[0].toUpperCase() : '?',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  /// 限额设置对话框
  Future<void> _showLimitDialog(_AppLimitItem item) async {
    int minutes = item.dailyMinutes > 0 ? item.dailyMinutes : 30;
    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => _LimitPickerSheet(
        appName: item.appName,
        initialMinutes: minutes,
        hasLimit: item.dailyMinutes > 0,
      ),
    );

    if (result == null) return;

    if (result == 0) {
      // 移除限额
      await EnforcementService.removeAppLimit(item.packageName);
    } else {
      // 设置限额
      await EnforcementService.setAppLimit(item.packageName, result);
    }
    _load();
  }
}

// ─── 数据模型 ──────────────────────────────────────────────────────────

class _AppLimitItem {
  final String packageName;
  final String appName;
  final int dailyMinutes;
  final int usedSeconds;

  const _AppLimitItem({
    required this.packageName,
    required this.appName,
    required this.dailyMinutes,
    required this.usedSeconds,
  });
}

// ─── 限额选择器底部面板 ──────────────────────────────────────────────

class _LimitPickerSheet extends StatefulWidget {
  final String appName;
  final int initialMinutes;
  final bool hasLimit;

  const _LimitPickerSheet({
    required this.appName,
    required this.initialMinutes,
    required this.hasLimit,
  });

  @override
  State<_LimitPickerSheet> createState() => _LimitPickerSheetState();
}

class _LimitPickerSheetState extends State<_LimitPickerSheet> {
  late int _minutes;
  static const List<int> _options = [15, 30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    _minutes = widget.initialMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('${widget.appName} 每日限额',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          // 选项快捷按钮
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _options.map((min) {
              final selected = _minutes == min;
              return ChoiceChip(
                label: Text('$min 分钟'),
                selected: selected,
                onSelected: (_) => setState(() => _minutes = min),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // 自定义滑块
          Row(
            children: [
              const Text('15'),
              Expanded(
                child: Slider(
                  value: _minutes.toDouble(),
                  min: 15,
                  max: 120,
                  divisions: 7, // 15, 30, 45, 60, 75, 90, 105, 120
                  label: '$_minutes 分钟',
                  onChanged: (v) => setState(() => _minutes = v.round()),
                ),
              ),
              const Text('120'),
            ],
          ),
          Center(
            child: Text(
              '$_minutes 分钟',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // 移除限额
              if (widget.hasLimit)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, 0),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('移除限额'),
                  ),
                ),
              if (widget.hasLimit) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _minutes),
                  child: const Text('确认'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
