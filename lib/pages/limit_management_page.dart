import 'package:flutter/material.dart';

import '../models/app_usage_session.dart';
import '../services/enforcement_service.dart';
import '../utils/format_utils.dart';

/// 限额管理 Tab：设置/查看每日使用限额
///
/// 数据源优先级：
/// 1. 今天已使用的 App（可靠性最高，来自 queryUsageSessions）
/// 2. 已设置限额的 App（可能不在今日记录中）
/// 3. 全部已安装 App（OPPO 兼容性问题，作为补充）
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
  List<_AppLimitItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    try {
      // ① 从已有会话构建 App 名称与用量
      final sessionMap = <String, _AppSessionInfo>{};
      for (final s in widget.todaySessions) {
        final existing = sessionMap[s.packageName];
        if (existing == null) {
          sessionMap[s.packageName] = _AppSessionInfo(
            appName: s.appName,
            totalSeconds: s.duration.inSeconds,
          );
        } else {
          sessionMap[s.packageName] = _AppSessionInfo(
            appName: existing.appName,
            totalSeconds: existing.totalSeconds + s.duration.inSeconds,
          );
        }
      }

      // ② 读取已有限额
      final limitMap = <String, int>{};
      try {
        final limits = await EnforcementService.getAppLimits();
        for (final l in limits) {
          limitMap[l['packageName'] as String] = l['dailyMinutes'] as int;
        }
      } catch (_) {}

      // ③ 补充：有会话但没有用量数据的 App（补用量）
      for (final entry in sessionMap.entries) {
        if (entry.value.totalSeconds == 0) {
          try {
            final secs = await EnforcementService.getAppDailyUsage(entry.key);
            sessionMap[entry.key] = _AppSessionInfo(
              appName: entry.value.appName,
              totalSeconds: secs,
            );
          } catch (_) {}
        }
      }

      // ④ 构建列表：合并会话 App + 有限额但今天未用的 App
      final seen = <String>{};
      final items = <_AppLimitItem>[];

      // 先加会话中的 App
      for (final entry in sessionMap.entries) {
        seen.add(entry.key);
        items.add(_AppLimitItem(
          packageName: entry.key,
          appName: entry.value.appName,
          dailyMinutes: limitMap[entry.key] ?? 0,
          usedSeconds: entry.value.totalSeconds,
        ));
      }

      // 再加有限额但今天没用过的
      for (final entry in limitMap.entries) {
        if (!seen.contains(entry.key)) {
          int used = 0;
          try { used = await EnforcementService.getAppDailyUsage(entry.key); } catch (_) {}
          items.add(_AppLimitItem(
            packageName: entry.key,
            appName: entry.key, // 只有包名，没有中文名
            dailyMinutes: entry.value,
            usedSeconds: used,
          ));
        }
      }

      // 有限额的排前面，按名称排序
      items.sort((a, b) {
        final aHas = a.dailyMinutes > 0 ? 0 : 1;
        final bHas = b.dailyMinutes > 0 ? 0 : 1;
        if (aHas != bHas) return aHas.compareTo(bHas);
        return a.appName.compareTo(b.appName);
      });

      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  IconCache get _icons => widget.iconCache;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_bottom, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('今天还没有使用记录', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      );
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

/// 从会话汇总的 App 信息
class _AppSessionInfo {
  final String appName;
  final int totalSeconds;

  const _AppSessionInfo({required this.appName, required this.totalSeconds});
}

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
